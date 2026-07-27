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

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler    = ref.read(audioHandlerProvider);
    final theme      = ref.watch(playerThemeProvider);
    final ambient    = ref.watch(ambientThemeProvider);
    final playerOpen = ref.watch(playerOpenProvider);

    if (playerOpen) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
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
      builder: (context, statSnap) {
        final isPlaying = statSnap.data?.playing ?? false;

        return StreamBuilder<Duration>(
          stream: handler.positionStream,
          builder: (context, posSnap) {
            final pos      = posSnap.data ?? Duration.zero;
            final dur      = handler.duration ?? Duration.zero;
            final progress = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            // Album-tinted background: backgroundDark is darkVibrant mixed 90% toward
            // black — gives each album its own dark identity without being garish.
            final bgColor = Color.lerp(
              ambient.backgroundDark, Colors.black, 0.50)!.withAlpha(0xEE);

            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: bgColor,
                  child: SafeArea(
                    top: false,
                    // Entire mini player opens the full player on tap.
                    // Buttons wrap their own GestureDetector to absorb taps
                    // so they don't propagate up and trigger navigation.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push('/player'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress line — album-colored active segment
                          Stack(children: [
                            Container(height: 2, color: Colors.white.withAlpha(0x0F)),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 2,
                                color: ambient.waveformActive,
                              ),
                            ),
                          ]),
                          // Content row
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                _ArtThumb(artUri: item.artUri, surface: theme.surface),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item.artist != null)
                                        Text(
                                          item.artist!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: ambient.waveformActive,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Buttons absorb taps so parent GestureDetector
                                // doesn't navigate when the user controls playback.
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {}, // absorb
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: ambient.waveformActive,
                                          size: 28,
                                        ),
                                        onPressed: () => isPlaying
                                            ? handler.pause()
                                            : handler.play(),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.skip_next,
                                          color: Colors.white.withAlpha(0x88),
                                          size: 24,
                                        ),
                                        onPressed: handler.skipToNext,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtThumb extends StatelessWidget {
  final Uri? artUri;
  final Color surface;
  const _ArtThumb({required this.artUri, required this.surface});

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(borderRadius: BorderRadius.circular(8));
    if (artUri == null) {
      return Container(width: 44, height: 44,
          decoration: decoration.copyWith(color: surface));
    }
    return CachedNetworkImage(
      imageUrl: artUri.toString(),
      width: 44, height: 44, fit: BoxFit.cover,
      imageBuilder: (_, provider) => Container(
        width: 44, height: 44,
        decoration: decoration.copyWith(
          image: DecorationImage(image: provider, fit: BoxFit.cover),
        ),
      ),
      placeholder: (_, _) =>
          Container(width: 44, height: 44, decoration: decoration.copyWith(color: surface)),
      errorWidget: (_, _, _) =>
          Container(width: 44, height: 44, decoration: decoration.copyWith(color: surface)),
    );
  }
}
