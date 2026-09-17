import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../audio/audio_handler.dart';
import '../providers.dart';
import '../theme/ambient_theme.dart';
import '../theme/vibe_theme.dart';

class DesktopPlayerBar extends ConsumerWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler    = ref.read(audioHandlerProvider);
    final theme      = ref.watch(playerThemeProvider);
    final ambient    = ref.watch(ambientThemeProvider);
    final playerOpen = ref.watch(playerOpenProvider);

    if (playerOpen) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (_, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox(height: 72);
        return _Bar(handler: handler, item: item, theme: theme, ambient: ambient);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final VibeAudioHandler handler;
  final MediaItem        item;
  final VibeTheme        theme;
  final AmbientTheme     ambient;

  const _Bar({
    required this.handler,
    required this.item,
    required this.theme,
    required this.ambient,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (_, statSnap) {
        final state     = statSnap.data;
        final isPlaying = state?.playing ?? false;
        final shuffleOn = state?.shuffleMode == AudioServiceShuffleMode.all;

        return StreamBuilder<Duration>(
          stream: handler.positionStream,
          builder: (_, posSnap) {
            final pos      = posSnap.data ?? Duration.zero;
            final dur      = handler.duration ?? Duration.zero;
            final progress = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            final bgColor = Color.lerp(
              ambient.backgroundDark, Colors.black, 0.55)!.withAlpha(0xF2);

            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border(
                      top: BorderSide(color: Colors.white.withAlpha(0x10)),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Thin progress line at top
                      _ProgressLine(
                        progress: progress,
                        dur: dur,
                        handler: handler,
                        accent: ambient.waveformActive,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              // ── Left: art + info ──────────────────────────
                              Expanded(
                                flex: 3,
                                child: GestureDetector(
                                  onTap: () => context.push('/player'),
                                  behavior: HitTestBehavior.opaque,
                                  child: Row(
                                    children: [
                                      _ArtThumb(artUri: item.artUri, surface: theme.surface),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color:      Colors.white,
                                                fontSize:   14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (item.artist != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                item.artist!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:    ambient.waveformActive,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // ── Center: controls ──────────────────────────
                              Expanded(
                                flex: 4,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.skip_previous_rounded,
                                            color: Colors.white.withAlpha(0xCC), size: 26),
                                          onPressed: handler.skipToPrevious,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () => isPlaying
                                              ? handler.pause()
                                              : handler.play(),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color:  ambient.waveformActive,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                              color: Colors.black,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.skip_next_rounded,
                                            color: Colors.white.withAlpha(0xCC), size: 26),
                                          onPressed: handler.skipToNext,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                    // Time labels
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        children: [
                                          Text(_fmt(pos), style: _timeStyle),
                                          const Spacer(),
                                          Text(_fmt(dur), style: _timeStyle),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Right: shuffle + volume ───────────────────
                              Expanded(
                                flex: 3,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.shuffle_rounded,
                                        size: 20,
                                        color: shuffleOn
                                            ? ambient.waveformActive
                                            : Colors.white.withAlpha(0x44),
                                      ),
                                      onPressed: () => handler.setShuffleMode(
                                        shuffleOn
                                            ? AudioServiceShuffleMode.none
                                            : AudioServiceShuffleMode.all,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _VolumeControl(handler: handler, accent: ambient.waveformActive),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static const _timeStyle = TextStyle(
    color:    Color(0x66FFFFFF),
    fontSize: 10,
    fontVariations: [FontVariation('wght', 500)],
  );
}

// ── Clickable progress line ───────────────────────────────────────────────────

class _ProgressLine extends StatelessWidget {
  final double           progress;
  final Duration         dur;
  final VibeAudioHandler handler;
  final Color            accent;

  const _ProgressLine({
    required this.progress,
    required this.dur,
    required this.handler,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _seek(context, d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _seek(context, d.localPosition.dx),
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(builder: (_, c) {
          return Stack(children: [
            Container(color: Colors.white.withAlpha(0x0F)),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(color: accent),
            ),
          ]);
        }),
      ),
    );
  }

  void _seek(BuildContext context, double dx) {
    if (dur == Duration.zero) return;
    final width = context.size?.width ?? 1;
    final ratio = (dx / width).clamp(0.0, 1.0);
    handler.seek(Duration(milliseconds: (dur.inMilliseconds * ratio).round()));
  }
}

// ── Volume control ────────────────────────────────────────────────────────────

class _VolumeControl extends StatefulWidget {
  final VibeAudioHandler handler;
  final Color            accent;
  const _VolumeControl({required this.handler, required this.accent});

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  double _volume = 1.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white.withAlpha(0x88),
          size: 18,
        ),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight:      2,
              thumbShape:       const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:     const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: widget.accent,
              inactiveTrackColor: Colors.white.withAlpha(0x22),
              thumbColor:       Colors.white,
              overlayColor:     Colors.white.withAlpha(0x18),
            ),
            child: Slider(
              value:    _volume,
              min:      0,
              max:      1,
              onChanged: (v) {
                setState(() => _volume = v);
                widget.handler.setVolume(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Album art thumbnail ───────────────────────────────────────────────────────

class _ArtThumb extends StatelessWidget {
  final Uri?  artUri;
  final Color surface;
  const _ArtThumb({required this.artUri, required this.surface});

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(borderRadius: BorderRadius.circular(8));
    if (artUri == null) {
      return Container(width: 48, height: 48,
          decoration: deco.copyWith(color: surface));
    }
    return CachedNetworkImage(
      imageUrl: artUri.toString(),
      width: 48, height: 48, fit: BoxFit.cover,
      imageBuilder: (_, p) => Container(
        width: 48, height: 48,
        decoration: deco.copyWith(
            image: DecorationImage(image: p, fit: BoxFit.cover)),
      ),
      placeholder: (_, _) =>
          Container(width: 48, height: 48, decoration: deco.copyWith(color: surface)),
      errorWidget: (_, _, _) =>
          Container(width: 48, height: 48, decoration: deco.copyWith(color: surface)),
    );
  }
}
