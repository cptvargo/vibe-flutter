import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_models.dart';
import '../api/jellyfin_api.dart';
import '../services/download_service.dart';
import '../services/genre_cluster_service.dart';
import '../services/recently_played_service.dart';
import '../services/last_played_service.dart';
import '../services/on_deck_service.dart';
import '../services/smart_shuffle.dart';

// ─── Playback mode ─────────────────────────────────────────────────────────────
enum PlaybackMode {
  none,      // 2.5 s silence gap between tracks (DJ mode off)
  gapless,   // no gap, no overlap (future: live albums)
  crossfade, // equal-power overlap — default (DJ mode on)
  smart,     // auto-select by media type (future)
}

// ─── Helpers ───────────────────────────────────────────────────────────────────
MediaItem _toMediaItem(VibeTrack t, {String playbackContext = 'album'}) {
  // Prefer local file if downloaded — transparent offline playback from
  // anywhere in the app, not just the Downloads screen.
  final localPath = DownloadService.localPathSync(t.id);
  final url = (localPath != null && File(localPath).existsSync())
      ? Uri.file(localPath).toString()
      : t.url;

  return MediaItem(
    id:       t.id,
    title:    t.title,
    artist:   t.artist,
    album:    t.album,
    duration: t.duration,
    artUri:   Uri.parse(t.artworkUrl),
    extras: {
      'url':               url,
      'albumId':           t.albumId,
      'artistId':          t.artistId,
      'albumArtist':       (t.raw['AlbumArtist'] as String?)?.isNotEmpty == true
                               ? t.raw['AlbumArtist'] as String
                               : t.artist.split(' & ').first,
      'colorUrl':          t.colorUrl,
      'blurHash':          t.blurHash,
      'durationMicros':    t.duration.inMicroseconds,
      'trackNumber':       t.trackNumber,
      'isAI':              t.isAI,
      'playbackContext':   playbackContext,
      'genres':            t.genres,
      'normalizationGain': t.normalizationGain,
    },
  );
}

// ─── Playback engine ───────────────────────────────────────────────────────────
//
// Architecture: dual-player, Dart-managed queue.
//
// Two physical AudioPlayers swap roles after each crossfade:
//
//   _primary   — the track the user currently hears (volume 1.0)
//   _secondary — preloading/playing the next track (volume 0→1 during fade)
//
// The queue is a plain Dart List<MediaItem>. Neither player ever uses
// ConcatenatingAudioSource. Each player holds exactly one source at a time.
//
// This eliminates the native decoder-flush click that occurs when just_audio's
// ConcatenatingAudioSource auto-advances: with our architecture the outgoing
// decoder drains silently to 0 before being stopped, and the incoming decoder
// has been running for seconds before the user hears it — no transient is
// possible.
//
// UI code must only subscribe to the stable forwarding streams on this class
// (positionStream, durationStream, etc.) — never to individual AudioPlayer
// streams, because the underlying player reference changes on every swap.

class VibeAudioHandler extends BaseAudioHandler with SeekHandler {
  // Physical players — references are stable for the lifetime of the handler.
  final _playerA = AudioPlayer();
  final _playerB = AudioPlayer();

  // Which player is currently primary. Toggled on every crossfade completion.
  bool _aIsPrimary = true;
  AudioPlayer get _primary   => _aIsPrimary ? _playerA : _playerB;
  AudioPlayer get _secondary => _aIsPrimary ? _playerB : _playerA;

  // ── Stable forwarding streams (UI subscribes here) ──────────────────────
  final _positionCtrl   = StreamController<Duration>.broadcast();
  final _durationCtrl   = StreamController<Duration?>.broadcast();
  final _shuffleCtrl    = StreamController<bool>.broadcast();
  final _loopModeCtrl   = StreamController<LoopMode>.broadcast();
  final _currentIdxCtrl = StreamController<int?>.broadcast();

  Stream<Duration>  get positionStream           => _positionCtrl.stream;
  Stream<Duration?> get durationStream           => _durationCtrl.stream;
  Stream<bool>      get shuffleModeEnabledStream => _shuffleCtrl.stream;
  Stream<LoopMode>  get loopModeStream           => _loopModeCtrl.stream;
  Stream<int?>      get currentIndexStream       => _currentIdxCtrl.stream;
  Duration?         get duration                 => _primary.duration;

  // ── Queue state (Dart-managed) ───────────────────────────────────────────
  List<MediaItem> _queue      = [];
  int             _queueIdx   = 0;
  LoopMode        _loopMode   = LoopMode.off;
  bool            _shuffle    = false;

  // True when the user explicitly paused (vs. system/output-change pause).
  // Used to prevent BT reconnect from auto-resuming a deliberate pause.
  bool _userPaused = false;
  bool get userPaused => _userPaused;

  // ── Sleep timer ──────────────────────────────────────────────────────────
  DateTime? _sleepAt; // null = off
  final _sleepCtrl = StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepRemainingStream => _sleepCtrl.stream;
  Duration? get sleepRemaining {
    if (_sleepAt == null) return null;
    final r = _sleepAt!.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  // minutes == 0 cancels the timer.
  void setSleepTimer(int minutes) {
    _sleepAt = minutes > 0 ? DateTime.now().add(Duration(minutes: minutes)) : null;
    _sleepCtrl.add(sleepRemaining);
  }

  // ── Playback mode / crossfade config ────────────────────────────────────
  PlaybackMode _mode        = PlaybackMode.crossfade;
  int          _overlapSec = 10; // how early the next song starts before the current ends
  final int    _fadeOutSec = 2;  // how long the current song fades out at the end

  // Volume tick interval. 50 ms gives ~20 fps — smooth and
  // not so frequent that it strains lower-end Android devices.
  static const _tickMs  = 50;
  static const _kGapMs  = 2000; // silence window when DJ mode is off

  // ── Crossfade runtime state ──────────────────────────────────────────────
  Timer? _fadeTimer;
  bool   _crossfading = false; // true from start of fade until player swap
  bool   _preloaded   = false; // secondary has a source loaded and buffered

  // ── Gap runtime state ────────────────────────────────────────────────────
  Timer? _gapTimer;
  bool   _inGap        = false; // true during the silence window
  int?   _gapTargetIdx;         // queue index we'll advance to at gap end

  // ── Listener subscriptions ───────────────────────────────────────────────
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>?    _posSub;
  StreamSubscription<Duration?>?   _durSub;

  // Suppresses spurious state events during source loads.
  bool _loading = false;

  // ── Serial operation queue ────────────────────────────────────────────────
  // All state-mutating commands are serialised here so they can never run
  // concurrently.  This mirrors the Plexamp TaskQueue pattern: every public
  // command is pushed onto the chain and only executes after the prior one
  // has fully completed.
  Future<void> _opQueue     = Future.value();
  int          _skipGen     = 0;     // incremented on every user-initiated skip
  bool         _naturalEndQueued = false; // prevents double-enqueue of natural end

  // Deduplicates Jellyfin 10-second progress pings.
  int _lastReportedSec = -1;

  VibeAudioHandler() {
    _wirePrimary();
  }

  // Convert a MediaItem's ReplayGain dB tag to a linear volume scalar.
  // Positive dB (quiet track boosted) is capped at 1.0 — just_audio can't
  // exceed unity gain, and we never want to clip a loud track upward.
  double _gainVolumeFor(MediaItem item) {
    final gainDb = item.extras?['normalizationGain'] as double?;
    if (gainDb == null) return 1.0;
    return (pow(10.0, gainDb / 20.0) as double).clamp(0.0, 1.0);
  }

  // ── Serial queue helpers ──────────────────────────────────────────────────
  // _enqueue: chain op onto _opQueue.  Prior errors are swallowed so a single
  // failing op never permanently breaks the chain.
  Future<void> _enqueue(Future<void> Function() op) =>
      _opQueue = _opQueue.then((_) => op(), onError: (_) => op());

  // _enqueueSkip: same as _enqueue but captures a generation number.
  // If another skip arrives before this one runs, the generation changes and
  // this op becomes a no-op — equivalent to Plexamp's TaskQueue.cancelTasks().
  Future<void> _enqueueSkip(Future<void> Function() op) {
    final gen = ++_skipGen;
    _naturalEndQueued = false; // a skip supersedes any pending natural-end
    return _opQueue = _opQueue.then(
      (_) async { if (_skipGen == gen) await op(); },
      onError: (_) async { if (_skipGen == gen) await op(); },
    );
  }

  // ── Wire all listeners to the current primary player ─────────────────────
  // Called once on init and again after every crossfade swap to redirect
  // event flow to the player that is now primary.
  void _wirePrimary() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();

    _stateSub = _primary.playerStateStream.listen(_onPrimaryState);

    // Position stream does two things: forward to _positionCtrl for the UI,
    // and drive the crossfade trigger and progress-reporting logic.
    _posSub = _primary.positionStream.listen((pos) {
      _positionCtrl.add(pos);
      _onPrimaryPosition(pos);
      _maybeSaveSession(pos);
      _tickSleepTimer();
    });

    _durSub = _primary.durationStream.listen((dur) {
      _durationCtrl.add(dur);
      // When just_audio reads the real duration from the file (e.g. a
      // downloaded track whose stored durationMicros was 0 because Jellyfin
      // returned RunTimeTicks:null), backfill the MediaItem so the lock screen
      // and audio_service also show the correct duration instead of 00:00.
      if (dur != null && dur > Duration.zero && _queueIdx < _queue.length) {
        final old = _queue[_queueIdx];
        if ((old.duration ?? Duration.zero) < const Duration(seconds: 1)) {
          final updated = old.copyWith(duration: dur);
          _queue[_queueIdx] = updated;
          queue.add(List.from(_queue));
          mediaItem.add(updated);
        }
      }
    });
  }

  // ── Primary player state → audio_service playbackState ───────────────────
  void _onPrimaryState(PlayerState state) {
    if (_loading) {
      // Stay suppressed until the new track actually starts playing.
      // This prevents the play button from flashing to "play" during the
      // stop→setAudioSource→play gap in _hardSkipTo / playTracks.
      if (state.playing) {
        _loading = false; // first playing:true → resume forwarding
      } else if (state.processingState == ProcessingState.idle) {
        // Suppress idle during the stop→setAudioSource→play sequence.
        // Do NOT clear _loading here: setAudioSource also transitions through
        // idle internally, and with _loading=false that second idle would fall
        // through to playbackState.add(idle), which deactivates the iOS audio
        // session — leaving the player in a "playing but silent" state.
        // _loading is cleared only when playing:true arrives (the line above).
        return;
      } else {
        return;
      }
    }

    // During a crossfade _finalizeCrossfade stops the old primary (now at
    // volume 0) while the new track is already audible.  That stop emits
    // (idle, false) here, which would make audio_service report "stopped" to
    // the lock-screen player and stale the transport controls.  Suppress it.
    if (_crossfading && state.processingState == ProcessingState.idle) return;

    playbackState.add(playbackState.value.copyWith(
      // 5-button layout: prev | ⟪10s | play/pause | 10s⟫ | next
      // Compact view (notification shade, lock screen) shows indices 0, 2, 4
      // so the user gets prev | play/pause | next — same as before.
      // Expanded notification shows all 5, matching YTM's layout.
      controls: [
        MediaControl.skipToPrevious,
        state.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (state.processingState) {
        ProcessingState.idle      => AudioProcessingState.idle,
        ProcessingState.loading   => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready     => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing:          state.playing,
      updatePosition:   _primary.position,
      bufferedPosition: _primary.bufferedPosition,
      speed:            _primary.speed,
    ));

    // Natural end of track — only act if NOT mid-crossfade.
    // During crossfade the primary is faded to 0 and stopped manually; any
    // completed events it emits before the stop are intentionally ignored.
    // Guard with _naturalEndQueued so rapid completed events don't double-enqueue.
    if (state.processingState == ProcessingState.completed && !_crossfading) {
      if (!_naturalEndQueued) {
        _naturalEndQueued = true;
        _enqueue(() async {
          if (!_naturalEndQueued) return; // cancelled by a skip
          _naturalEndQueued = false;
          await _onTrackNaturalEnd();
        });
      }
    }
  }

  // ── Sleep timer tick ─────────────────────────────────────────────────────
  int _lastSleepBroadcastSec = -1;

  void _tickSleepTimer() {
    if (_sleepAt == null) return;
    final remaining = sleepRemaining!;
    // Broadcast an update at most once per second to keep the countdown UI smooth.
    final sec = remaining.inSeconds;
    if (sec != _lastSleepBroadcastSec) {
      _lastSleepBroadcastSec = sec;
      _sleepCtrl.add(remaining);
    }
    if (remaining == Duration.zero) {
      _sleepAt = null;
      _userPaused = true; // treat as explicit pause so BT reconnect won't resume
      _primary.pause();
    }
  }

  // ── Position-driven crossfade trigger ────────────────────────────────────
  // Runs on every primary position tick (suppressed during crossfade).
  // Two thresholds:
  //   (crossfadeSec + 5) s before end  →  preload secondary into buffer
  //   crossfadeSec before end           →  begin fade
  void _onPrimaryPosition(Duration pos) {
    if (_loading || _crossfading) return;

    // Jellyfin progress ping every 10 seconds, deduplicated.
    final item = mediaItem.value;
    if (item != null) {
      final sec = pos.inSeconds;
      if (sec > 0 && sec % 10 == 0 && sec != _lastReportedSec) {
        _lastReportedSec = sec;
        JellyfinApi.reportPlaybackProgress(item.id, pos.inMicroseconds * 10);
      }
    }

    if (_mode != PlaybackMode.crossfade) return;

    final dur = _primary.duration;
    // Skip crossfade for tracks shorter than 2× the overlap window.
    if (dur == null || dur.inSeconds < _overlapSec * 2) return;

    final nextIdx = _nextIndex;
    if (nextIdx == null) return; // last track — no crossfade

    final remaining = dur - pos;

    if (!_preloaded && remaining.inSeconds <= (_overlapSec + 5)) {
      _preloadSecondary(nextIdx);
    }

    if (!_crossfading &&
        remaining.inSeconds <= _overlapSec &&
        remaining.inMilliseconds > 300) {
      _beginCrossfade(remaining, nextIdx);
    }
  }

  // ── Preload ───────────────────────────────────────────────────────────────
  // Loads the next track's source into _secondary so it is buffered before
  // the fade begins. The player stays paused at position 0.
  Future<void> _preloadSecondary(int nextIdx) async {
    if (_preloaded) return;
    _preloaded = true; // set before await to prevent duplicate calls
    try {
      final item = _queue[nextIdx];
      final url  = item.extras?['url'] as String? ?? '';
      if (url.isEmpty) { _preloaded = false; return; }
      // Stop secondary before loading so _cancelCrossfade can't race with an
      // in-flight setAudioSource (which would throw and kill _hardSkipTo).
      await _secondary.stop();
      if (!_preloaded) return; // cancelled by _cancelCrossfade while stopping
      await _secondary.setAudioSource(
          AudioSource.uri(Uri.parse(url), tag: item));
    } catch (_) {
      _preloaded = false;
    }
  }

  // ── Crossfade ─────────────────────────────────────────────────────────────
  // Two-phase overlap:
  //   Phase 1 — both songs play at full volume for (_overlapSec - _fadeOutSec) s
  //   Phase 2 — current song fades out over _fadeOutSec s; next song unchanged
  Future<void> _beginCrossfade(Duration remaining, int nextIdx) async {
    if (_crossfading) return;
    _crossfading = true; // prevent re-entry from concurrent position ticks
    // Advance _queueIdx NOW, before any await. skipToPrevious checks _queueIdx
    // to compute _prevIndex while _crossfading=true. If we wait until after
    // _secondary.play() (the original location), a skip that fires between here
    // and that point sees the old index and computes the wrong previous track —
    // or null when Song A is index 0 — and _hardSkipTo is never called, leaving
    // the engine in a cancelled-crossfade-but-no-source state.
    _queueIdx = nextIdx;

    final nextItem = _queue[nextIdx];

    // Load secondary now if preload didn't complete in time.
    if (!_preloaded) {
      final url = nextItem.extras?['url'] as String? ?? '';
      if (url.isEmpty) { _crossfading = false; return; }
      try {
        await _secondary.setAudioSource(
            AudioSource.uri(Uri.parse(url), tag: nextItem));
      } catch (_) {
        _crossfading = false;
        return;
      }
    }

    // Guard: crossfade may have been cancelled while we awaited setAudioSource.
    if (!_crossfading) return;

    // Next song starts at its normalised volume immediately.
    await _secondary.setVolume(_gainVolumeFor(nextItem));
    // Guard again: _cancelCrossfade may have run while setVolume was awaited.
    // Without this, _secondary.play() fires after a skip, the stale fade timer
    // starts running against the new primary, and audio dies.
    if (!_crossfading) return;
    _secondary.play();

    // Advance all metadata to the incoming track immediately.
    // Lock screen, notification, and UI all show the new song as soon as the
    // crossfade begins — this is the behaviour users expect from premium apps.
    _reportStopped();
    _lastReportedSec = -1;
    mediaItem.add(nextItem);
    _currentIdxCtrl.add(_queueIdx);
    _saveCurrentItem(nextItem);
    _reportStarted(nextItem.id);
    queue.add(List.unmodifiable(_queue));

    // Rewire position/duration forwarding to secondary so the seek bar tracks
    // the incoming track's progress during the overlap window.
    _posSub?.cancel();
    _durSub?.cancel();
    _posSub = _secondary.positionStream.listen(_positionCtrl.add);
    _durSub = _secondary.durationStream.listen(_durationCtrl.add);

    // Phase 1: let both songs play at full volume.
    // Schedule the fade-out to begin _fadeOutSec before the current track ends.
    final overlapMs = remaining.inMilliseconds
        .clamp(_fadeOutSec * 1000 + 50, _overlapSec * 1000);
    final waitMs = overlapMs - (_fadeOutSec * 1000);

    _fadeTimer?.cancel();
    _fadeTimer = Timer(Duration(milliseconds: waitMs), _startFadeOut);
  }

  // Phase 2: fade current song out over _fadeOutSec seconds.
  void _startFadeOut() {
    // Guard: the one-shot Timer that calls this cannot be cancelled once its
    // callback is already in the event queue.  If _cancelCrossfade ran before
    // this callback got a chance to execute, bail out — do NOT create the
    // periodic timer or the periodic ticks will fade out the skipped-to track.
    if (!_crossfading) return;
    final totalSteps = (_fadeOutSec * 1000 / _tickMs).round().clamp(1, 9999);
    int step = 0;
    _fadeTimer = Timer.periodic(Duration(milliseconds: _tickMs), (timer) {
      if (!_crossfading) { timer.cancel(); return; }
      step++;
      final t = (step / totalSteps).clamp(0.0, 1.0);
      _primary.setVolume((1.0 - t).clamp(0.0, 1.0));
      if (t >= 1.0) {
        timer.cancel();
        _finalizeCrossfade();
      }
    });
  }

  Future<void> _finalizeCrossfade() async {
    // Guard against a stale call arriving after _cancelCrossfade already ran
    // (e.g. the last periodic tick was queued when cancel() was called).
    // Without this guard, _primary.stop() kills the skipped-to track and the
    // subsequent _aIsPrimary swap wires listeners to the wrong player.
    if (!_crossfading) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;

    // Primary volume is already at 0.0.  Stopping a silent player drains the
    // audio pipeline into silence — no transient, no click.
    await _primary.stop();
    await _primary.setVolume(1.0); // reset for its next role as secondary

    // Swap roles.  The old secondary (which has been playing cleanly for
    // several seconds) becomes the new primary.
    _aIsPrimary  = !_aIsPrimary;
    _crossfading = false;
    _preloaded   = false;

    // Rewire all listeners to the new primary.
    _wirePrimary();
  }

  Future<void> _cancelCrossfade() async {
    if (!_crossfading && !_preloaded) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final wasFading = _crossfading;
    _crossfading    = false;
    _preloaded      = false;
    try { await _secondary.stop(); } catch (_) {}
    try { await _secondary.setVolume(1.0); } catch (_) {}
    if (wasFading) {
      // Restore primary to its track's gain (it was being faded down).
      // _hardSkipTo will overwrite this immediately, but the brief moment
      // between cancel and the next setAudioSource should not be silent.
      final gainVol = _queueIdx < _queue.length
          ? _gainVolumeFor(_queue[_queueIdx])
          : 1.0;
      await _primary.setVolume(gainVol);
    }
    _wirePrimary(); // restore primary forwarding after the cancel
  }

  // ── Natural track completion (no crossfade) ───────────────────────────────
  Future<void> _onTrackNaturalEnd() async {
    final nextIdx = _nextIndex;
    if (nextIdx == null) {
      // Queue finished — remove the album from On Deck so a fully-played
      // album doesn't keep showing a stale progress bar.
      final item    = mediaItem.value;
      final albumId = item?.extras?['albumId'] as String?;
      final context = item?.extras?['playbackContext'] as String?;
      if (albumId != null && albumId.isNotEmpty && context == 'album') {
        OnDeckService.removeSession(albumId);
      }
      _reportStopped();
      mediaItem.add(null);
      queue.add([]);
      return;
    }
    if (_mode == PlaybackMode.none) {
      _startGap(nextIdx);
    } else {
      await _hardSkipTo(nextIdx);
    }
  }

  // ── Gap (silence window between tracks) ──────────────────────────────────
  //
  // Starts a 2 s silence window then advances to the next track.
  // Any user action (pause, skip, new queue) cancels the gap cleanly.
  void _startGap(int nextIdx) {
    _inGap        = true;
    _gapTargetIdx = nextIdx;
    _gapTimer = Timer(const Duration(milliseconds: _kGapMs), () {
      _gapTimer     = null;
      _inGap        = false;
      _gapTargetIdx = null;
      if (nextIdx >= 0 && nextIdx < _queue.length) {
        _enqueue(() => _hardSkipTo(nextIdx));
      }
    });
  }

  void _cancelGap() {
    _gapTimer?.cancel();
    _gapTimer     = null;
    _inGap        = false;
    _gapTargetIdx = null;
  }

  // ── Hard skip (immediate cut, no fade) ───────────────────────────────────
  Future<void> _hardSkipTo(int index) async {
    _naturalEndQueued = false; // skip supersedes any pending natural-end
    _loading = true; // set before cancel so position ticks during cancel are suppressed
    await _cancelCrossfade();
    // _cancelCrossfade calls _wirePrimary(), which may immediately receive a
    // (ready, playing:true) event from the old primary (it was mid-fade and
    // still playing). That clears _loading prematurely, causing the subsequent
    // _primary.stop() to forward an idle state to audio_service and kill the
    // audio session before the new source loads. Re-asserting here closes that window.
    _loading = true;

    _reportStopped();
    _queueIdx        = index;
    _lastReportedSec = -1;
    final item = _queue[index];
    mediaItem.add(item);
    _currentIdxCtrl.add(_queueIdx);
    _saveCurrentItem(item);

    // Re-check for a local file at skip time — the track may have been
    // downloaded after the queue was originally built.
    final localPath = DownloadService.localPathSync(item.id);
    final url = (localPath != null && File(localPath).existsSync())
        ? Uri.file(localPath).toString()
        : (item.extras?['url'] as String? ?? '');
    try {
      await _primary.stop();
      // Immediately reset the position so the on-phone timer and car/BT
      // MediaSession display both show 0:00 instead of holding the
      // end-of-track value until just_audio's periodic ticker fires.
      _positionCtrl.add(Duration.zero);
      playbackState.add(playbackState.value.copyWith(
        updatePosition: Duration.zero,
      ));
      await _primary.setVolume(_gainVolumeFor(item));
      await _primary.setAudioSource(
          AudioSource.uri(Uri.parse(url), tag: item));
      _reportStarted(item.id);
      queue.add(List.unmodifiable(_queue));
      _primary.play(); // _loading cleared by _onPrimaryState on first playing:true
    } catch (_) {
      _loading = false;
    }
  }

  // ── Persist current track for cold-start restore ──────────────────────────
  void _saveCurrentItem(MediaItem item) => LastPlayedService.save(item);

  // ── Persist session for On Deck / Jump Back In (every 5 s of playback) ────
  int _lastSavedPosSec = -1;

  void _maybeSaveSession(Duration pos) {
    if (_loading) return;
    final sec = pos.inSeconds;
    if (sec < 5) return;
    if ((sec - _lastSavedPosSec).abs() < 5) return;
    _lastSavedPosSec = sec;
    _saveAlbumSession(pos);
  }

  void _saveAlbumSession(Duration pos) {
    final item = mediaItem.value;
    if (item == null) return;
    final albumId = item.extras?['albumId'] as String?;
    if (albumId == null || albumId.isEmpty) return;
    final context = item.extras?['playbackContext'] as String?;
    if (context != 'album') return; // only album playback updates On Deck

    // Cumulative album progress: sum completed tracks + current position.
    int completedMs = 0;
    for (int i = 0; i < _queueIdx; i++) {
      completedMs += _queue[i].duration?.inMilliseconds ?? 0;
    }
    final playedMs = completedMs + pos.inMilliseconds;
    final totalMs  = _queue.fold<int>(
        0, (sum, m) => sum + (m.duration?.inMilliseconds ?? 0));

    // Preserve the best known data: never regress progress, never lose totalMs.
    final existing          = OnDeckService.getSession(albumId);
    final effectivePlayedMs = max(playedMs, existing?.playedMs ?? 0);
    final effectiveTotalMs  = totalMs > 0 ? totalMs : (existing?.totalMs ?? 0);

    // Skip if there's nothing meaningful to save (album just barely started
    // and no prior session exists to preserve).
    if (effectiveTotalMs == 0 || (existing == null && pos.inSeconds < 5)) return;

    OnDeckService.saveSession(
      albumId:         albumId,
      albumTitle:      item.album  ?? '',
      artist:          item.artist ?? '',
      artUrl:          item.artUri?.toString() ?? '',
      playedMs:        effectivePlayedMs,
      totalMs:         effectiveTotalMs,
      trackPositionMs: pos.inMilliseconds,
      queueIndex:      _queueIdx,
      trackNumber:     item.extras?['trackNumber'] as int?,
      trackTitle:      item.title,
      trackDurationMs: item.duration?.inMilliseconds ?? 0,
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> playTracks(
    List<VibeTrack> tracks, {
    int startIndex = 0,
    int startPositionMs = 0,
    String playbackContext = 'album',
  }) {
    // Snapshot the current album's progress before the queue is replaced so
    // switching albums doesn't lose the in-progress session.
    _saveAlbumSession(_primary.position);
    _userPaused = false; // new queue = new intent to play
    _sleepAt    = null;  // explicit play always cancels any sleep timer
    _sleepCtrl.add(null);
    _cancelGap();
    _naturalEndQueued = false;
    ++_skipGen; // cancel any pending enqueued skip
    return _enqueue(() async {
      _loading = true; // set before cancel so position ticks during cancel are suppressed
      await _cancelCrossfade();
      _loading = true; // re-assert: _wirePrimary inside _cancelCrossfade may have cleared it
      _reportStopped();

      _queue           = tracks.map((t) => _toMediaItem(t, playbackContext: playbackContext)).toList();
      _queueIdx        = startIndex.clamp(0, _queue.length - 1);
      _lastReportedSec = -1;

      final item = _queue[_queueIdx];
      final url  = item.extras?['url'] as String? ?? '';

      queue.add(List.unmodifiable(_queue));
      mediaItem.add(item);
      _currentIdxCtrl.add(_queueIdx);
      _saveCurrentItem(item);

      await _primary.stop();
      await _primary.setVolume(_gainVolumeFor(item));
      try {
        await _primary.setAudioSource(AudioSource.uri(Uri.parse(url), tag: item));
        if (startPositionMs > 0) {
          await _primary.seek(Duration(milliseconds: startPositionMs));
        }
      } catch (_) {
        _loading = false;
        return;
      }

      _reportStarted(item.id);
      _primary.play(); // _loading cleared by _onPrimaryState on first playing:true

      // When playing a single track outside an album, auto-fill the queue.
      // ViBE Out uses a pure random fill; other contexts use InstantMix.
      if (tracks.length == 1 && playbackContext != 'album') {
        final seed = tracks[startIndex.clamp(0, tracks.length - 1)];
        if (playbackContext == 'vibe_out') {
          _autoFillWithRandomTracks(seed);
        } else {
          _autoFillWithInstantMix(seed);
        }
      }
    });
  }

  Future<void> _autoFillWithInstantMix(VibeTrack seed) async {
    try {
      final mix = await JellyfinApi.getInstantMixTracks(seed.id, limit: 50);

      // Determine which dynamic genre cluster the seed belongs to so the
      // queue stays stylistically consistent for any genre — not just the
      // two hardcoded Christian sub-genres.
      final seedGenres = ((seed.raw['Genres'] as List?) ?? [])
          .cast<String>()
          .map((g) => g.toLowerCase().trim())
          .toSet();

      // Ensure the cluster cache is warm; if getSimilarArtistsByGenre already
      // primed it this session this is a no-op.
      await GenreClusterService.getClusters();
      final cluster = GenreClusterService.clusterFor(seedGenres);

      final toAdd = mix.where((t) {
        if (t.id == seed.id) return false;
        if (cluster == null) return true; // no recognised cluster — keep all
        final tGenres = ((t.raw['Genres'] as List?) ?? [])
            .cast<String>()
            .map((g) => g.toLowerCase().trim())
            .toSet();
        // Keep tracks that share the cluster OR carry only generic tags.
        return cluster.matchesAny(tGenres) ||
            tGenres.every(GenreClusterService.isGeneric);
      }).toList();

      if (toAdd.isEmpty) return;
      for (final t in toAdd) {
        _queue.add(_toMediaItem(t, playbackContext: 'instant_mix'));
      }
      queue.add(List.unmodifiable(_queue));
    } catch (_) {}
  }

  Future<void> _autoFillWithRandomTracks(VibeTrack seed) async {
    try {
      // Try genre-matched random first, fall back to full-library random.
      List<VibeTrack> tracks = seed.genres.isNotEmpty
          ? await JellyfinApi.getRandomTracksByGenres(seed.genres, limit: 50)
          : [];
      if (tracks.isEmpty) {
        tracks = await JellyfinApi.getRandomTracks(limit: 50);
      }
      final usedIds = _queue.map((m) => m.id).toSet();
      final toAdd   = tracks.where((t) => !usedIds.contains(t.id)).toList();
      if (toAdd.isEmpty) return;
      for (final t in toAdd) {
        _queue.add(_toMediaItem(t, playbackContext: 'vibe_out'));
      }
      queue.add(List.unmodifiable(_queue));
    } catch (_) {}
  }

  Future<void> addToQueue(VibeTrack track) async {
    _queue.add(_toMediaItem(track, playbackContext: 'vibe_out'));
    queue.add(List.unmodifiable(_queue));
  }

  // Insert track immediately after the current position.
  // If the queue is empty, starts playing the track.
  Future<void> playNext(VibeTrack track) async {
    if (_queue.isEmpty) {
      await playTracks([track], playbackContext: 'vibe_out');
      return;
    }
    final insertIdx = (_queueIdx + 1).clamp(0, _queue.length);
    _queue.insert(insertIdx, _toMediaItem(track, playbackContext: 'vibe_out'));
    queue.add(List.unmodifiable(_queue));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    if (oldIndex == _queueIdx) {
      _queueIdx = newIndex;
    } else if (oldIndex < _queueIdx && newIndex >= _queueIdx) {
      _queueIdx--;
    } else if (oldIndex > _queueIdx && newIndex <= _queueIdx) {
      _queueIdx++;
    }
    _currentIdxCtrl.add(_queueIdx);
    queue.add(List.unmodifiable(_queue));
  }

  // Playback mode and crossfade duration are runtime-configurable so a future
  // settings screen can expose them without touching the engine.
  void setPlaybackMode(PlaybackMode mode) {
    _mode = mode;
    // Switching out of gap mode while mid-gap → play next track immediately
    // so the user doesn't sit in silence wondering what happened.
    if (mode != PlaybackMode.none && _inGap) {
      final target = _gapTargetIdx;
      _cancelGap();
      if (target != null) _enqueue(() => _hardSkipTo(target));
    }
  }

  void setCrossfadeDuration(int seconds) => _overlapSec = seconds.clamp(3, 30);

  // ── BaseAudioHandler overrides ────────────────────────────────────────────

  @override
  Future<void> play() async {
    _userPaused = false;
    // If the queue is empty but a track was restored from cold-start, load it
    // on first play tap rather than at startup (avoids unnecessary network use).
    if (_queue.isEmpty) {
      final item = mediaItem.value;
      if (item == null) return;
      // Re-check for a local file — extras['url'] may be a stream URL from
      // before the track was downloaded, or downloaded after the last save.
      final localPath = DownloadService.localPathSync(item.id);
      final url = (localPath != null && File(localPath).existsSync())
          ? Uri.file(localPath).toString()
          : (item.extras?['url'] as String? ?? '');
      if (url.isEmpty) return;
      _queue    = [item];
      _queueIdx = 0;
      _loading  = true;
      queue.add(List.unmodifiable(_queue));
      try {
        await _primary.setVolume(_gainVolumeFor(item));
        await _primary.setAudioSource(AudioSource.uri(Uri.parse(url), tag: item));
        _reportStarted(item.id);
        // Cold-start: queue has only this one track. Fill it from InstantMix in
        // the background so playback continues past this single restored track.
        _coldStartAutoFill(item.id);
      } catch (_) {
        _loading = false;
        return;
      }
    }
    return _primary.play(); // _loading cleared by _onPrimaryState on first playing:true
  }

  // Fetch an InstantMix for the cold-start seed track and append results to
  // the queue. Only runs when the queue is exactly 1 item (cold-start guard).
  void _coldStartAutoFill(String trackId) {
    JellyfinApi.getInstantMixTracks(trackId, limit: 50).then((tracks) {
      if (_queue.length != 1 || _queueIdx != 0) return;
      final newItems = tracks.skip(1).map((t) => _toMediaItem(t)).toList();
      if (newItems.isEmpty) return;
      _queue = [_queue[0], ...newItems];
      queue.add(List.unmodifiable(_queue));
    }).catchError((_) {});
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    _preloaded  = false;
    _cancelGap(); // gap is an auto-advance — explicit pause cancels it
    await _primary.pause();
    // Save immediately on pause so On Deck / Jump Back In update without
    // waiting for the next periodic tick.
    _saveAlbumSession(_primary.position);
  }

  // Pause due to a system/output event (headphone unplug, BT disconnect).
  // Does NOT set _userPaused so BT reconnect can still auto-resume.
  Future<void> systemPause() async {
    await _primary.pause();
    _saveAlbumSession(_primary.position);
  }

  @override
  Future<void> stop() {
    _cancelGap();
    _naturalEndQueued = false;
    ++_skipGen;
    return _enqueue(() async {
      await _cancelCrossfade();
      _reportStopped();
      await _primary.stop();
    });
  }

  @override Future<void> seek(Duration position) => _primary.seek(position);

  Future<void> setVolume(double volume) => _primary.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> skipToNext() {
    _cancelGap();
    // During a crossfade _queueIdx is already the incoming track, so _nextIndex
    // correctly resolves to the track after it — no special-case needed.
    return _enqueueSkip(() async {
      final next = _nextIndex;
      if (next == null) return;
      await _hardSkipTo(next);
    });
  }

  @override
  Future<void> skipToPrevious() {
    _cancelGap();
    return _enqueueSkip(() async {
      if (_crossfading) {
        // During a crossfade the user sees the secondary (incoming) track.
        // Mirror the normal ">3 s → restart / ≤3 s → go back" logic against secondary.
        if (_secondary.position.inSeconds > 3) {
          await _hardSkipTo(_queueIdx); // restart the incoming track from 0
        } else {
          final prev = _prevIndex; // _queueIdx is already at N+1, so prev = N
          if (prev != null) await _hardSkipTo(prev);
        }
        return;
      }
      if (_primary.position.inSeconds > 3) {
        await _primary.seek(Duration.zero);
        return;
      }
      final prev = _prevIndex;
      if (prev != null) await _hardSkipTo(prev);
    });
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _cancelGap();
    if (index < 0 || index >= _queue.length) return Future.value();
    return _enqueueSkip(() => _hardSkipTo(index));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one  => LoopMode.one,
      AudioServiceRepeatMode.all  => LoopMode.all,
      _                           => LoopMode.off,
    };
    _loopModeCtrl.add(_loopMode);
    // Mirror repeat state into the MediaSession so the car dashboard reflects it
    // and the car's steering-wheel repeat button gets confirmation feedback.
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    // Persist so repeat state survives process kills (car stop, OOM).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('vibe_repeat_v1', repeatMode.index);
    } catch (_) {}
    // LoopMode is managed here in Dart, not by the AudioPlayer, so we do not
    // call _primary.setLoopMode(). _nextIndex handles all loop logic.
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _shuffle = shuffleMode == AudioServiceShuffleMode.all;
    if (_shuffle && _queue.isNotEmpty) {
      // Keep the current track at the front; shuffle everything after it.
      final current = _queue[_queueIdx];
      final rest = [..._queue]..removeAt(_queueIdx);
      final spaced = smartShuffle<MediaItem>(rest, (m) => m.artist ?? '');
      _queue    = [current, ...spaced];
      _queueIdx = 0;
      _currentIdxCtrl.add(_queueIdx);
      queue.add(List.unmodifiable(_queue));
    }
    _shuffleCtrl.add(_shuffle);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    // Persist so shuffle state survives process kills (car stop, OOM).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vibe_shuffle_v1', _shuffle);
    } catch (_) {}
  }

  // ── Queue index helpers ───────────────────────────────────────────────────

  int? get _nextIndex {
    if (_queue.isEmpty) return null;
    if (_loopMode == LoopMode.one) return _queueIdx;
    final next = _queueIdx + 1;
    if (next >= _queue.length) {
      return _loopMode == LoopMode.all ? 0 : null;
    }
    return next;
  }

  int? get _prevIndex {
    if (_queue.isEmpty) return null;
    final prev = _queueIdx - 1;
    if (prev < 0) {
      return _loopMode == LoopMode.all ? _queue.length - 1 : null;
    }
    return prev;
  }

  // ── Jellyfin reporting + recently played ──────────────────────────────────

  void _reportStopped() {
    final item = mediaItem.value;
    if (item == null) return;
    JellyfinApi.reportPlaybackStopped(
        item.id, _primary.position.inMicroseconds * 10);
  }

  void _reportStarted(String itemId) {
    JellyfinApi.reportPlaybackStart(itemId);
    final idx = _queue.indexWhere((m) => m.id == itemId);
    if (idx < 0) return;
    final item = _queue[idx];
    RecentlyPlayedService.add(VibeTrack(
      id:         item.id,
      url:        item.extras?['url']      as String? ?? '',
      title:      item.title,
      artist:     item.artist              ?? '',
      album:      item.album               ?? '',
      albumId:    item.extras?['albumId']  as String?,
      artistId:   item.extras?['artistId'] as String?,
      artworkUrl: item.artUri?.toString()  ?? '',
      colorUrl:   item.extras?['colorUrl'] as String? ?? '',
      blurHash:   item.extras?['blurHash'] as String?,
      duration:   item.duration            ?? Duration.zero,
      raw:        {},
      isAI:       item.extras?['isAI']     as bool? ?? false,
    ));
  }
}
