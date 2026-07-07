import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../api/jellyfin_models.dart';
import '../api/jellyfin_api.dart';
import '../services/recently_played_service.dart';

MediaItem _toMediaItem(VibeTrack t) => MediaItem(
  id:       t.id,
  title:    t.title,
  artist:   t.artist,
  album:    t.album,
  duration: t.duration,
  artUri:   Uri.parse(t.artworkUrl),
  extras:   {
    'url':           t.url,
    'albumId':       t.albumId,
    'artistId':      t.artistId,
    'colorUrl':      t.colorUrl,
    'blurHash':      t.blurHash,
    'durationMicros': t.duration.inMicroseconds,
    'isAI':          t.isAI,
  },
);

AudioSource _toAudioSource(VibeTrack t) => AudioSource.uri(
  Uri.parse(t.url),
  tag: _toMediaItem(t),
);

class VibeAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player      = AudioPlayer();
  final _xfadePlayer = AudioPlayer(); // incoming track during crossfade

  static const _crossfadeSec    = 8;   // seconds of overlap
  static const _xfadeIntervalMs = 80;  // volume update interval

  Timer? _xfadeTimer;
  bool   _crossfading   = false;
  bool   _loadingTracks = false; // suppresses currentIndexStream during setAudioSources

  VibeAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    _player.playerStateStream.listen((state) {
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
        updatePosition:   _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed:            _player.speed,
      ));

      // Only clear state when the last track genuinely finishes —
      // spurious completed events can fire mid-queue during crossfade/seek.
      if (state.processingState == ProcessingState.completed) {
        final idx = _player.currentIndex ?? 0;
        if (idx >= queue.value.length - 1) {
          Future.delayed(const Duration(milliseconds: 100), () {
            mediaItem.add(null);
            queue.add([]);
          });
        }
      }
    });

    _player.currentIndexStream.listen((index) {
      if (index == null || _loadingTracks) return;
      final q = queue.value;

      // Report the outgoing track as stopped before switching
      final prev = mediaItem.value;
      if (prev != null) {
        JellyfinApi.reportPlaybackStopped(prev.id, _player.position.inMicroseconds * 10);
      }

      if (index < q.length) {
        mediaItem.add(q[index]);
        _reportProgressStart(q[index].id);
      }
      // Auto-advance fired — sync player position to xfade player and take over
      if (_crossfading) _finalizeCrossfade();
    });

    _player.positionStream.listen((pos) {
      final item = mediaItem.value;
      if (item == null) return;

      // Jellyfin progress reporting
      if (pos.inSeconds > 0 && pos.inSeconds % 10 == 0) {
        JellyfinApi.reportPlaybackProgress(item.id, pos.inMicroseconds * 10);
      }

      // Crossfade trigger: start when remaining ≤ crossfadeSec
      if (!_crossfading) {
        final dur = _player.duration;
        if (dur != null && dur.inSeconds > _crossfadeSec * 2) {
          final remaining = dur - pos;
          if (remaining.inSeconds <= _crossfadeSec && remaining.inMilliseconds > 500) {
            _beginCrossfade(remaining);
          }
        }
      }
    });
  }

  // ── Crossfade ───────────────────────────────────────────────────────────────

  Future<void> _beginCrossfade(Duration remaining) async {
    final currentIndex = _player.currentIndex ?? 0;
    final q            = queue.value;
    final nextIndex    = currentIndex + 1;
    if (nextIndex >= q.length) return; // last track — no crossfade

    _crossfading = true;

    final nextUrl = q[nextIndex].extras?['url'] as String? ?? '';
    if (nextUrl.isEmpty) { _crossfading = false; return; }

    try {
      await _xfadePlayer.setAudioSource(AudioSource.uri(Uri.parse(nextUrl)));
      await _xfadePlayer.setVolume(0.0);
      await _xfadePlayer.play();
    } catch (e) {
      _crossfading = false;
      return;
    }

    final totalMs  = remaining.inMilliseconds.clamp(500, _crossfadeSec * 1000);
    final totalSteps = totalMs ~/ _xfadeIntervalMs;
    int step = 0;

    _xfadeTimer?.cancel();
    _xfadeTimer = Timer.periodic(
      const Duration(milliseconds: _xfadeIntervalMs),
      (timer) {
        if (!_crossfading) { timer.cancel(); return; }
        step++;
        final t      = (step / totalSteps).clamp(0.0, 1.0);
        // Cosine easing — sounds more natural than linear
        final eased  = (1 - cos(t * pi)) / 2;
        _player.setVolume((1.0 - eased).clamp(0.0, 1.0));
        _xfadePlayer.setVolume(eased.clamp(0.0, 1.0));
        if (t >= 1.0) timer.cancel();
      },
    );
  }

  // Called when _player auto-advances to the next track
  Future<void> _finalizeCrossfade() async {
    _xfadeTimer?.cancel();
    _xfadeTimer = null;

    final syncPos = _xfadePlayer.position;

    // Stop xfade player and restore main volume first
    await _xfadePlayer.stop();
    await _player.setVolume(1.0);

    // Only seek if duration is known and syncPos is within track bounds —
    // seeking before duration is available can cause a spurious `completed`
    // state emission that prematurely dismisses the player screen.
    final dur = _player.duration;
    if (syncPos > Duration.zero && dur != null && syncPos < dur) {
      try {
        await _player.seek(syncPos);
      } catch (_) {}
    }

    _crossfading = false;
  }

  Future<void> _cancelCrossfade() async {
    if (!_crossfading) return;
    _xfadeTimer?.cancel();
    _xfadeTimer  = null;
    _crossfading = false;
    await _xfadePlayer.stop();
    await _player.setVolume(1.0);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> playTracks(List<VibeTrack> tracks, {int startIndex = 0}) async {
    await _cancelCrossfade();
    final sources     = tracks.map(_toAudioSource).toList();
    final items       = tracks.map(_toMediaItem).toList();
    final clampedStart = startIndex.clamp(0, items.length - 1);
    _loadingTracks = true;
    await _player.stop();
    queue.add(items);
    mediaItem.add(items[clampedStart]);
    await _player.setAudioSources(sources, initialIndex: clampedStart);
    _loadingTracks = false;
    _reportProgressStart(items[clampedStart].id);
    _player.play(); // intentionally not awaited — play() resolves when audio ends
  }

  Future<void> addToQueue(VibeTrack track) async {
    await _player.addAudioSource(_toAudioSource(track));
    queue.add([...queue.value, _toMediaItem(track)]);
  }

  // ── BaseAudioHandler overrides ─────────────────────────────────────────────

  @override Future<void> play()  => _player.play();
  @override Future<void> pause() => _player.pause();
  @override Future<void> stop() async {
    final item = mediaItem.value;
    if (item != null) {
      JellyfinApi.reportPlaybackStopped(item.id, _player.position.inMicroseconds * 10);
    }
    return _player.stop();
  }
  @override Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _cancelCrossfade();
    await _player.seekToNext();
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    await _cancelCrossfade();
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
    await _player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _cancelCrossfade();
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one  => LoopMode.one,
      AudioServiceRepeatMode.all  => LoopMode.all,
      _                           => LoopMode.off,
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
        shuffleMode == AudioServiceShuffleMode.all);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  void _reportProgressStart(String itemId) {
    JellyfinApi.reportPlaybackStart(itemId);
    // Add to local recently-played history
    final q = queue.value;
    final track = q.where((m) => m.id == itemId).firstOrNull;
    if (track != null) {
      RecentlyPlayedService.add(VibeTrack(
        id:         track.id,
        url:        track.extras?['url']      as String? ?? '',
        title:      track.title,
        artist:     track.artist ?? '',
        album:      track.album  ?? '',
        albumId:    track.extras?['albumId']  as String?,
        artistId:   track.extras?['artistId'] as String?,
        artworkUrl: track.artUri?.toString()  ?? '',
        colorUrl:   track.extras?['colorUrl'] as String? ?? '',
        blurHash:   track.extras?['blurHash'] as String?,
        duration:   track.duration ?? Duration.zero,
        raw:        {},
        isAI:       track.extras?['isAI']     as bool? ?? false,
      ));
    }
  }

  AudioPlayer get player => _player;
}
