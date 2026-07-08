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
    'url':            t.url,
    'albumId':        t.albumId,
    'artistId':       t.artistId,
    'colorUrl':       t.colorUrl,
    'blurHash':       t.blurHash,
    'durationMicros': t.duration.inMicroseconds,
    'isAI':           t.isAI,
  },
);

AudioSource _toAudioSource(VibeTrack t) => AudioSource.uri(
  Uri.parse(t.url),
  tag: _toMediaItem(t),
);

class VibeAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();

  // Single-player volume fade — avoids the seek/buffer gap of a dual-player
  // crossfade. Fades out over the last few seconds, lets just_audio's native
  // gapless advance fire, then fades the new track back in.
  static const _fadeOutSec = 4;   // seconds before end to start fade-out
  static const _fadeInMs   = 1200; // ms to fade new track in
  static const _tickMs     = 80;   // volume update interval

  Timer? _fadeTimer;
  bool   _fadingOut     = false;
  bool   _loadingTracks = false;

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

      final prev = mediaItem.value;
      if (prev != null) {
        JellyfinApi.reportPlaybackStopped(prev.id, _player.position.inMicroseconds * 10);
      }

      if (index < q.length) {
        mediaItem.add(q[index]);
        _reportProgressStart(q[index].id);
      }

      // Track advanced — if we were fading out, cancel and fade the new track in
      if (_fadingOut) {
        _fadeTimer?.cancel();
        _fadingOut = false;
        _startFadeIn();
      }
    });

    _player.positionStream.listen((pos) {
      final item = mediaItem.value;
      if (item == null) return;

      if (pos.inSeconds > 0 && pos.inSeconds % 10 == 0) {
        JellyfinApi.reportPlaybackProgress(item.id, pos.inMicroseconds * 10);
      }

      // Begin fade-out when within _fadeOutSec of the end
      if (!_fadingOut) {
        final dur = _player.duration;
        if (dur != null && dur.inSeconds > _fadeOutSec * 2) {
          final remaining = dur - pos;
          if (remaining.inSeconds <= _fadeOutSec && remaining.inMilliseconds > 200) {
            _startFadeOut(remaining.inMilliseconds);
          }
        }
      }
    });
  }

  // ── Volume fades ────────────────────────────────────────────────────────────

  void _startFadeOut(int remainingMs) {
    _fadingOut = true;
    final clampedMs = remainingMs.clamp(200, _fadeOutSec * 1000);
    final steps = clampedMs ~/ _tickMs;
    int step = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(
      Duration(milliseconds: _tickMs),
      (timer) {
        step++;
        final t = (step / steps).clamp(0.0, 1.0);
        // Cosine easing — sounds more natural than linear
        final vol = (cos(t * pi / 2)).clamp(0.0, 1.0);
        _player.setVolume(vol);
        if (t >= 1.0) timer.cancel();
      },
    );
  }

  void _startFadeIn() {
    _player.setVolume(0.0);
    final steps = _fadeInMs ~/ _tickMs;
    int step = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(
      Duration(milliseconds: _tickMs),
      (timer) {
        step++;
        final t = (step / steps).clamp(0.0, 1.0);
        final vol = sin(t * pi / 2).clamp(0.0, 1.0);
        _player.setVolume(vol);
        if (t >= 1.0) {
          _player.setVolume(1.0);
          timer.cancel();
        }
      },
    );
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer  = null;
    _fadingOut  = false;
    _player.setVolume(1.0);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> playTracks(List<VibeTrack> tracks, {int startIndex = 0}) async {
    _cancelFade();
    final sources      = tracks.map(_toAudioSource).toList();
    final items        = tracks.map(_toMediaItem).toList();
    final clampedStart = startIndex.clamp(0, items.length - 1);
    _loadingTracks = true;
    await _player.stop();
    queue.add(items);
    mediaItem.add(items[clampedStart]);
    await _player.setAudioSources(sources, initialIndex: clampedStart);
    // Explicit seek — just_audio_windows doesn't reliably honour initialIndex.
    if (clampedStart > 0) {
      await _player.seek(Duration.zero, index: clampedStart);
    }
    _loadingTracks = false;
    _reportProgressStart(items[clampedStart].id);
    _player.play();
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
    _cancelFade();
    await _player.seekToNext();
    await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    _cancelFade();
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
    await _player.play();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _cancelFade();
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
    final q     = queue.value;
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
