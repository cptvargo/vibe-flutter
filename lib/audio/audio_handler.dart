import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../api/jellyfin_models.dart';
import '../api/jellyfin_api.dart';
import '../services/download_service.dart';
import '../services/genre_cluster_service.dart';
import '../services/recently_played_service.dart';
import '../services/last_played_service.dart';
import '../services/on_deck_service.dart';

// ─── Playback mode ─────────────────────────────────────────────────────────────
// Only crossfade is implemented now. The enum exists so Smart/Gapless modes
// can be wired in later without changing the public API.
enum PlaybackMode {
  none,      // hard cut (future: silence between tracks)
  gapless,   // no gap, no overlap (future: live albums, DJ mixes)
  crossfade, // equal-power overlap — active implementation
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
      'url':             url,
      'albumId':         t.albumId,
      'artistId':        t.artistId,
      'colorUrl':        t.colorUrl,
      'blurHash':        t.blurHash,
      'durationMicros':  t.duration.inMicroseconds,
      'trackNumber':     t.trackNumber,
      'isAI':            t.isAI,
      'playbackContext': playbackContext,
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
  List<MediaItem> _queue    = [];
  int             _queueIdx = 0;
  LoopMode        _loopMode = LoopMode.off;
  bool            _shuffle  = false;

  // ── Playback mode / crossfade config ────────────────────────────────────
  PlaybackMode _mode         = PlaybackMode.crossfade;
  int          _crossfadeSec = 6; // configurable, default 6 s

  // Volume tick interval. 50 ms gives ~20 fps — smooth and
  // not so frequent that it strains lower-end Android devices.
  static const _tickMs = 50;

  // ── Crossfade runtime state ──────────────────────────────────────────────
  Timer? _fadeTimer;
  bool   _crossfading = false; // true from start of fade until player swap
  bool   _preloaded   = false; // secondary has a source loaded and buffered

  // ── Listener subscriptions ───────────────────────────────────────────────
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>?    _posSub;
  StreamSubscription<Duration?>?   _durSub;

  // Suppresses spurious state events during source loads.
  bool _loading = false;

  // Deduplicates Jellyfin 10-second progress pings.
  int _lastReportedSec = -1;

  VibeAudioHandler() {
    _wirePrimary();
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
    });

    _durSub = _primary.durationStream.listen(_durationCtrl.add);
  }

  // ── Primary player state → audio_service playbackState ───────────────────
  void _onPrimaryState(PlayerState state) {
    if (_loading) {
      // Stay suppressed until the new track actually starts playing.
      // This prevents the play button from flashing to "play" during the
      // stop→setAudioSource→play gap in _hardSkipTo / playTracks.
      if (state.playing) {
        _loading = false; // first playing:true → resume forwarding
      } else {
        return;
      }
    }

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        state.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
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
    if (state.processingState == ProcessingState.completed && !_crossfading) {
      _onTrackNaturalEnd();
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
    // Skip crossfade for tracks shorter than 2× the fade window — they would
    // begin fading almost immediately after starting.
    if (dur == null || dur.inSeconds < _crossfadeSec * 2) return;

    final nextIdx = _nextIndex;
    if (nextIdx == null) return; // last track — no crossfade

    final remaining = dur - pos;

    if (!_preloaded && remaining.inSeconds <= (_crossfadeSec + 5)) {
      _preloadSecondary(nextIdx);
    }

    if (!_crossfading &&
        remaining.inSeconds <= _crossfadeSec &&
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
      await _secondary.setAudioSource(
          AudioSource.uri(Uri.parse(url), tag: item));
    } catch (_) {
      _preloaded = false;
    }
  }

  // ── Crossfade ─────────────────────────────────────────────────────────────
  Future<void> _beginCrossfade(Duration remaining, int nextIdx) async {
    if (_crossfading) return;
    _crossfading = true; // prevent re-entry from concurrent position ticks

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

    // Secondary plays from position 0 at silence.
    await _secondary.setVolume(0.0);
    _secondary.play(); // not awaited — resolves only when the track ends

    // Advance all metadata to the incoming track immediately.
    // Lock screen, notification, and UI all show the new song as soon as the
    // crossfade begins — this is the behaviour users expect from premium apps.
    _reportStopped();
    _queueIdx        = nextIdx;
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

    final totalMs    = remaining.inMilliseconds.clamp(300, _crossfadeSec * 1000);
    final totalSteps = (totalMs / _tickMs).round().clamp(1, 9999);
    int step = 0;

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(Duration(milliseconds: _tickMs), (timer) {
      step++;
      final t = (step / totalSteps).clamp(0.0, 1.0);

      // Equal-power fade curves: cos²(θ) + sin²(θ) = 1.
      // Constant total loudness across the transition — no perceived dip or bump.
      final outVol = cos(t * pi / 2).clamp(0.0, 1.0);
      final inVol  = sin(t * pi / 2).clamp(0.0, 1.0);

      _primary.setVolume(outVol);
      _secondary.setVolume(inVol);

      if (t >= 1.0) {
        timer.cancel();
        _finalizeCrossfade();
      }
    });
  }

  Future<void> _finalizeCrossfade() async {
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
    await _secondary.stop();
    await _secondary.setVolume(1.0);
    if (wasFading) await _primary.setVolume(1.0);
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
    await _hardSkipTo(nextIdx);
  }

  // ── Hard skip (immediate cut, no fade) ───────────────────────────────────
  Future<void> _hardSkipTo(int index) async {
    await _cancelCrossfade();
    _loading = true;

    _reportStopped();
    _queueIdx        = index;
    _lastReportedSec = -1;
    final item = _queue[index];
    mediaItem.add(item);
    _currentIdxCtrl.add(_queueIdx);
    _saveCurrentItem(item);

    final url = item.extras?['url'] as String? ?? '';
    try {
      await _primary.stop();
      await _primary.setVolume(1.0);
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

    OnDeckService.saveSession(
      albumId:         albumId,
      albumTitle:      item.album  ?? '',
      artist:          item.artist ?? '',
      artUrl:          item.artUri?.toString() ?? '',
      playedMs:        playedMs,
      totalMs:         totalMs,
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
  }) async {
    // Snapshot the current album's progress before the queue is replaced so
    // switching albums doesn't lose the in-progress session.
    _saveAlbumSession(_primary.position);
    await _cancelCrossfade();
    _loading = true;
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
    await _primary.setVolume(1.0);
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

    // When playing a single track outside an album, auto-fill queue with
    // Jellyfin InstantMix so the listener gets a radio-like experience.
    if (tracks.length == 1 && playbackContext != 'album') {
      _autoFillWithInstantMix(tracks[startIndex.clamp(0, tracks.length - 1)]);
    }
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
  void setPlaybackMode(PlaybackMode mode) => _mode = mode;
  void setCrossfadeDuration(int seconds)  => _crossfadeSec = seconds.clamp(1, 15);

  // ── BaseAudioHandler overrides ────────────────────────────────────────────

  @override
  Future<void> play() async {
    // If the queue is empty but a track was restored from cold-start, load it
    // on first play tap rather than at startup (avoids unnecessary network use).
    if (_queue.isEmpty) {
      final item = mediaItem.value;
      if (item == null) return;
      final url = item.extras?['url'] as String? ?? '';
      if (url.isEmpty) return;
      _queue    = [item];
      _queueIdx = 0;
      _loading  = true;
      queue.add(List.unmodifiable(_queue));
      try {
        await _primary.setVolume(1.0);
        await _primary.setAudioSource(AudioSource.uri(Uri.parse(url), tag: item));
        _reportStarted(item.id);
      } catch (_) {
        _loading = false;
        return;
      }
    }
    return _primary.play(); // _loading cleared by _onPrimaryState on first playing:true
  }

  @override
  Future<void> pause() async {
    await _primary.pause();
    // Save immediately on pause so On Deck / Jump Back In update without
    // waiting for the next periodic tick.
    _saveAlbumSession(_primary.position);
  }

  @override
  Future<void> stop() async {
    await _cancelCrossfade();
    _reportStopped();
    return _primary.stop();
  }

  @override Future<void> seek(Duration position) => _primary.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_crossfading) {
      await _hardSkipTo(_queueIdx);
      return;
    }
    final next = _nextIndex;
    if (next == null) return;
    await _hardSkipTo(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_primary.position.inSeconds > 3) {
      await _primary.seek(Duration.zero);
      return;
    }
    final prev = _prevIndex;
    if (prev != null) await _hardSkipTo(prev);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _hardSkipTo(index);
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
      rest.shuffle();
      _queue    = [current, ...rest];
      _queueIdx = 0;
      _currentIdxCtrl.add(_queueIdx);
      queue.add(List.unmodifiable(_queue));
    }
    _shuffleCtrl.add(_shuffle);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
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
