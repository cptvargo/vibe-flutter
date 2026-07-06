import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../api/jellyfin_models.dart';
import '../api/jellyfin_api.dart';

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
    'colorUrl':      t.colorUrl,
    'blurHash':      t.blurHash,
    'durationMicros': t.duration.inMicroseconds,
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
  bool   _crossfading = false;

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

      // When the queue finishes, clear state so mini player disappears
      if (state.processingState == ProcessingState.completed) {
        Future.delayed(const Duration(milliseconds: 100), () {
          mediaItem.add(null);
          queue.add([]);
        });
      }
    });

    _player.currentIndexStream.listen((index) {
      if (index == null) return;
      final q = queue.value;
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

    // Sync _player to where _xfadePlayer already is so the track position is right
    final syncPos = _xfadePlayer.position;
    if (syncPos > Duration.zero) {
      await _player.seek(syncPos);
    }
    await _player.setVolume(1.0);
    await _xfadePlayer.stop();
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
    final sources = tracks.map(_toAudioSource).toList();
    final items   = tracks.map(_toMediaItem).toList();
    await _player.stop();
    queue.add(items);
    await _player.setAudioSources(sources, initialIndex: startIndex);
    _player.play(); // intentionally not awaited — play() resolves when audio ends
  }

  Future<void> addToQueue(VibeTrack track) async {
    await _player.addAudioSource(_toAudioSource(track));
    queue.add([...queue.value, _toMediaItem(track)]);
  }

  // ── BaseAudioHandler overrides ─────────────────────────────────────────────

  @override Future<void> play()  => _player.play();
  @override Future<void> pause() => _player.pause();
  @override Future<void> stop()  => _player.stop();
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
  }

  AudioPlayer get player => _player;
}
