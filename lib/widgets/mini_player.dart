import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../audio/audio_handler.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler    = ref.read(audioHandlerProvider);
    final theme      = ref.watch(themeProvider);
    final playerOpen = ref.watch(playerOpenProvider);

    // Hide while the full player screen is on the stack
    if (playerOpen) return const SizedBox.shrink();

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return _Bar(handler: handler, item: item, theme: theme);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final VibeAudioHandler handler;
  final MediaItem item;
  final VibeTheme theme;

  const _Bar({required this.handler, required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, statSnap) {
        final isPlaying = statSnap.data?.playing ?? false;

        return StreamBuilder<Duration>(
          stream: handler.player.positionStream,
          builder: (context, posSnap) {
            final pos      = posSnap.data ?? Duration.zero;
            final dur      = handler.player.duration ?? Duration.zero;
            final progress = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withAlpha(0xBF),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress line
                        Stack(children: [
                          Container(height: 2, color: Colors.white.withAlpha(0x0F)),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(height: 2, color: theme.accent),
                          ),
                        ]),
                        // Bar row
                        GestureDetector(
                          onTap: () => context.push('/player'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10,
                            ),
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
                                        style: TextStyle(
                                          color: theme.textColor,
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
                                            color: theme.textDim,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Play / pause
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: theme.accentBright,
                                    size: 28,
                                  ),
                                  onPressed: () =>
                                      isPlaying ? handler.pause() : handler.play(),
                                ),
                                // Skip next
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next,
                                    color: theme.textDim,
                                    size: 24,
                                  ),
                                  onPressed: handler.skipToNext,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
