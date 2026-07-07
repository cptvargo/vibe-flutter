import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../audio/audio_handler.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

const _kAlbumSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <rect x="3" y="3" width="18" height="18" rx="3" stroke="#000000" stroke-width="1.5"/>
  <circle cx="12" cy="12" r="4.5" stroke="#000000" stroke-width="1.5"/>
  <circle cx="12" cy="12" r="1.5" fill="#000000"/>
</svg>''';

const _kArtistSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">
  <circle cx="12" cy="8" r="4" stroke="#000000" stroke-width="1.5"/>
  <path d="M4 20c0-4.418 3.582-8 8-8s8 3.582 8 8" stroke="#000000" stroke-width="1.5" stroke-linecap="round"/>
</svg>''';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  late final AnimationController _snapCtrl;
  Animation<double>? _snapAnim;
  StreamSubscription<PlaybackState>? _completionSub;
  // Store notifier ref so we can safely use it in dispose()
  StateController<bool>? _playerOpenCtrl;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // Store notifier reference for use in dispose() — don't set state here
    _playerOpenCtrl = ref.read(playerOpenProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final handler = ref.read(audioHandlerProvider);
      _completionSub = handler.playbackState.listen((state) {
        if (state.processingState == AudioProcessingState.completed && mounted) {
          // Only dismiss when the last track genuinely finished
          final idx = handler.player.currentIndex ?? 0;
          final isLast = idx >= handler.queue.value.length - 1;
          if (isLast) _animateDismiss();
        }
      });
    });
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    _snapCtrl.dispose();
    _playerOpenCtrl?.state = false; // safe — stored reference, not ref.read()
    super.dispose();
  }

  void _animateDismiss() {
    // Let mini player reappear on the underlying screen as player slides away
    _playerOpenCtrl?.state = false;
    final screenH = MediaQuery.of(context).size.height;
    _snapAnim = Tween<double>(begin: _dragOffset, end: screenH)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeIn));
    _snapAnim!.addListener(() {
      if (mounted) setState(() => _dragOffset = _snapAnim!.value);
    });
    _snapCtrl.forward(from: 0).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy > 0 || _dragOffset > 0) {
      setState(() => _dragOffset = (_dragOffset + d.delta.dy).clamp(0.0, double.infinity));
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final screenH = MediaQuery.of(context).size.height;
    final velocity = d.primaryVelocity ?? 0;
    if (velocity > 500 || _dragOffset > screenH * 0.28) {
      _animateDismiss();
    } else {
      // Snap back up
      _snapAnim = Tween<double>(begin: _dragOffset, end: 0)
          .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
      _snapAnim!.addListener(() {
        if (mounted) setState(() => _dragOffset = _snapAnim!.value);
      });
      _snapCtrl.forward(from: 0).then((_) {
        if (mounted) setState(() => _dragOffset = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler   = ref.read(audioHandlerProvider);
    final theme     = ref.watch(themeProvider);
    final screenH   = MediaQuery.of(context).size.height;
    // As the player slides down, the underlying page is revealed
    final revealT   = (_dragOffset / screenH).clamp(0.0, 1.0);
    final barrierAlpha = ((1.0 - revealT) * 0x99).round(); // 0x99 ≈ 60% black

    return Stack(
      children: [
        // Barrier — dims the underlying page, fades as player drags down
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withAlpha(barrierAlpha),
            ),
          ),
        ),

        // Player card — slides down on drag, sits on top of barrier
        Transform.translate(
          offset: Offset(0, _dragOffset),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: StreamBuilder<MediaItem?>(
              stream: handler.mediaItem,
              builder: (context, snap) {
                final item = snap.data;
                if (item == null) {
                  return Scaffold(
                    backgroundColor: Colors.black,
                    body: const SizedBox.expand(),
                  );
                }
                return _Body(handler: handler, item: item, theme: theme);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Background + safe-area wrapper ─────────────────────────────────────────
class _Body extends StatelessWidget {
  final VibeAudioHandler handler;
  final MediaItem        item;
  final VibeTheme        theme;

  const _Body({required this.handler, required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final artUrl = item.artUri?.toString();

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Solid theme color base — visible even when art is loading
          ColoredBox(color: theme.background),
          // Blurred album art layered on top
          if (artUrl != null)
            CachedNetworkImage(
              imageUrl: artUrl,
              fit: BoxFit.cover,
              imageBuilder: (_, imageProvider) => ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Image(image: imageProvider, fit: BoxFit.cover,
                    width: double.infinity, height: double.infinity),
              ),
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget:  (_, _, _) => const SizedBox.shrink(),
            ),
          // Accent glow at top
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [theme.accent.withAlpha(0x66), Colors.transparent],
                stops: const [0.0, 0.45],
              ),
            ),
          ),
          // Dark vignette fading art into theme.background at bottom
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(0x44),
                  theme.background.withAlpha(0xCC),
                  theme.background,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: _Content(
              handler: handler,
              item: item,
              theme: theme,
              artUrl: artUrl,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Main content column ─────────────────────────────────────────────────────
class _Content extends ConsumerWidget {
  final VibeAudioHandler handler;
  final MediaItem        item;
  final VibeTheme        theme;
  final String?          artUrl;

  const _Content({
    required this.handler,
    required this.item,
    required this.theme,
    this.artUrl,
  });

  void _showOptions(BuildContext context, WidgetRef ref, MediaItem item, VibeTheme theme) {
    final albumId  = item.extras?['albumId']  as String?;
    final artistId = item.extras?['artistId'] as String?;
    // Capture router before any navigation; GoRouter is app-lifetime stable.
    final router = GoRouter.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: false,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(0x44),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (albumId != null)
              ListTile(
                leading: SvgPicture.string(
                  _kAlbumSvg,
                  width: 24, height: 24,
                  colorFilter: ColorFilter.mode(theme.accentBright, BlendMode.srcIn),
                ),
                title: Text('Go to Album',
                    style: TextStyle(color: theme.textColor)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  // Dismiss the player and show the mini player on the album screen.
                  ref.read(playerOpenProvider.notifier).state = false;
                  router.go(
                    '/album/$albumId'
                    '?name=${Uri.encodeComponent(item.album ?? '')}'
                    '&artist=${Uri.encodeComponent(item.artist ?? '')}',
                  );
                },
              ),
            if (item.artist != null && item.artist!.isNotEmpty)
              ListTile(
                leading: SvgPicture.string(
                  _kArtistSvg,
                  width: 24, height: 24,
                  colorFilter: ColorFilter.mode(theme.accentBright, BlendMode.srcIn),
                ),
                title: Text('Go to Artist',
                    style: TextStyle(color: theme.textColor)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  ref.read(playerOpenProvider.notifier).state = false;
                  String? id = artistId ?? await JellyfinApi.getArtistIdByName(item.artist!);
                  if (id != null) {
                    router.go(
                      '/artist/$id'
                      '?name=${Uri.encodeComponent(item.artist ?? '')}',
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fireMix  = ref.watch(fireMixProvider);
    final isFired  = fireMix.any((t) => t.id == item.id);

    return Column(
      children: [
        // Top bar: drag handle + options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Invisible spacer to balance the options button
              const SizedBox(width: 48),
              // Centered drag-down handle pill
              Expanded(
                child: Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(0x44),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_horiz,
                    color: Colors.white.withAlpha(0xBB)),
                onPressed: () => _showOptions(context, ref, item, theme),
              ),
            ],
          ),
        ),

        // Album art — expands to fill available vertical space
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Use the smaller of available width or height so the square
                  // fills the space properly on both phones and wide desktop windows
                  final size = min(constraints.maxWidth, constraints.maxHeight)
                      .clamp(100.0, 520.0);
                  return Container(
                    width: size, height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: theme.accent.withAlpha(0x55),
                          blurRadius: 48,
                          spreadRadius: 4,
                          offset: const Offset(0, 16),
                        ),
                        const BoxShadow(
                          color: Colors.black54,
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: artUrl != null
                          ? CachedNetworkImage(
                              imageUrl: artUrl!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: theme.surface),
                              errorWidget: (_, _, _) => Container(color: theme.surface),
                            )
                          : Container(color: theme.surface),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Title, artist, like + seekbar + controls
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
          child: StreamBuilder<PlaybackState>(
            stream: handler.playbackState,
            builder: (context, statSnap) {
              final isPlaying = statSnap.data?.playing ?? false;
              return StreamBuilder<Duration>(
                stream: handler.player.positionStream,
                builder: (context, posSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = handler.player.duration
                      ?? item.duration
                      ?? Duration.zero;
                  final progress = dur.inMilliseconds > 0
                      ? (pos.inMilliseconds / dur.inMilliseconds)
                            .clamp(0.0, 1.0)
                            .toDouble()
                      : 0.0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Track title + like button
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(0xBB),
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isFired ? Icons.whatshot : Icons.whatshot_outlined,
                              color: isFired
                                  ? const Color(0xFFFF6B1A) // always orange flame
                                  : Colors.white.withAlpha(0x55),
                              size: 26,
                            ),
                            onPressed: () {
                              final extras = item.extras ?? {};
                              final track = VibeTrack(
                                id:         item.id,
                                url:        extras['url'] as String?
                                                ?? JellyfinApi.streamUrl(item.id),
                                title:      item.title,
                                artist:     item.artist ?? '',
                                album:      item.album ?? '',
                                albumId:    extras['albumId'] as String?,
                                artworkUrl: item.artUri?.toString() ?? '',
                                colorUrl:   extras['colorUrl'] as String? ?? '',
                                blurHash:   extras['blurHash'] as String?,
                                duration:   item.duration ?? Duration(
                                  microseconds: extras['durationMicros'] as int? ?? 0,
                                ),
                                raw:        {},
                              );
                              ref.read(fireMixProvider.notifier).toggle(track);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Waveform seek bar
                      _WaveformSeekBar(
                        progress: progress,
                        trackId: item.id,
                        theme: theme,
                        onSeek: (ratio) => handler.seek(Duration(
                          milliseconds: (ratio * dur.inMilliseconds).round(),
                        )),
                      ),

                      // Timestamps
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos),
                                style: TextStyle(
                                    color: Colors.white.withAlpha(0x88),
                                    fontSize: 12)),
                            Text(_fmt(dur),
                                style: TextStyle(
                                    color: Colors.white.withAlpha(0x88),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Main controls: prev / play+pause / next
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            iconSize: 36,
                            icon: Icon(Icons.skip_previous_rounded,
                                color: theme.accentBright),
                            onPressed: handler.skipToPrevious,
                          ),
                          GestureDetector(
                            onTap: () =>
                                isPlaying ? handler.pause() : handler.play(),
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: theme.accent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.accent.withAlpha(0xAA),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                          IconButton(
                            iconSize: 36,
                            icon: Icon(Icons.skip_next_rounded,
                                color: theme.accentBright),
                            onPressed: handler.skipToNext,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Secondary: shuffle / repeat / queue
                      _SecondaryControls(handler: handler, theme: theme),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Shuffle + repeat + queue row ────────────────────────────────────────────
class _SecondaryControls extends StatelessWidget {
  final VibeAudioHandler handler;
  final VibeTheme        theme;
  const _SecondaryControls({required this.handler, required this.theme});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: handler.player.shuffleModeEnabledStream,
      builder: (context, shuffleSnap) {
        final shuffleOn = shuffleSnap.data ?? false;
        return StreamBuilder<LoopMode>(
          stream: handler.player.loopModeStream,
          builder: (context, loopSnap) {
            final loop = loopSnap.data ?? LoopMode.off;
            final accentOn   = theme.accentBright;
            final accentOff  = Colors.white.withAlpha(0x55);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(Icons.shuffle_rounded,
                      color: shuffleOn ? accentOn : accentOff),
                  onPressed: () => handler.setShuffleMode(
                    shuffleOn
                        ? AudioServiceShuffleMode.none
                        : AudioServiceShuffleMode.all,
                  ),
                ),
                // Repeat (off → all → one → off)
                IconButton(
                  icon: Icon(
                    loop == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    color: loop != LoopMode.off ? accentOn : accentOff,
                  ),
                  onPressed: () {
                    final next = switch (loop) {
                      LoopMode.off => AudioServiceRepeatMode.all,
                      LoopMode.all => AudioServiceRepeatMode.one,
                      _            => AudioServiceRepeatMode.none,
                    };
                    handler.setRepeatMode(next);
                  },
                ),
                // Queue
                IconButton(
                  icon: Icon(Icons.queue_music_rounded, color: accentOff),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => _QueueSheet(handler: handler, theme: theme),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Queue bottom sheet ──────────────────────────────────────────────────────
class _QueueSheet extends StatelessWidget {
  final VibeAudioHandler handler;
  final VibeTheme        theme;
  const _QueueSheet({required this.handler, required this.theme});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StreamBuilder<int?>(
            stream: handler.player.currentIndexStream,
            builder: (context, indexSnap) {
              final currentIndex = indexSnap.data ?? 0;
              final tracks = handler.queue.value;

              return Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(0x44),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Text(
                          'Up Next',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tracks.length} tracks',
                          style: TextStyle(
                            color: Colors.white.withAlpha(0x66),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  // Track list
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final track = tracks[i];
                        final isCurrent = i == currentIndex;
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: track.artUri != null
                                ? CachedNetworkImage(
                                    imageUrl: track.artUri.toString(),
                                    width: 44, height: 44,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) =>
                                        Container(width: 44, height: 44, color: theme.background),
                                  )
                                : Container(width: 44, height: 44, color: theme.background),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? theme.accentBright : Colors.white,
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          subtitle: Text(
                            track.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withAlpha(0x66), fontSize: 13),
                          ),
                          trailing: isCurrent
                              ? Icon(Icons.equalizer_rounded, color: theme.accentBright, size: 20)
                              : null,
                          onTap: () {
                            handler.skipToQueueItem(i);
                            Navigator.pop(context);
                          },
                        ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ── Waveform seek bar ───────────────────────────────────────────────────────
class _WaveformSeekBar extends StatelessWidget {
  final double    progress; // 0.0 – 1.0
  final String    trackId;
  final VibeTheme theme;
  final ValueChanged<double> onSeek; // emits ratio 0.0 – 1.0

  const _WaveformSeekBar({
    required this.progress,
    required this.trackId,
    required this.theme,
    required this.onSeek,
  });

  void _handleTap(BuildContext context, Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos);
    onSeek((local.dx / box.size.width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:               (d) => _handleTap(context, d.globalPosition),
      onHorizontalDragUpdate:  (d) => _handleTap(context, d.globalPosition),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            progress:      progress,
            activeColor:   theme.accentBright,
            inactiveColor: Colors.white.withAlpha(0x30),
          ),
          // Pass trackId in as a key so the painter knows which heights to use
          key: ValueKey(trackId),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color  activeColor;
  final Color  inactiveColor;

  // Heights shared across repaints via the ValueKey — set once per track
  static final Map<Key, List<double>> _heightCache = {};

  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  static List<double> _buildHeights(int seed, int count) {
    final rng = Random(seed);
    return List.generate(count, (i) {
      // Bell-curve envelope: centre bars taller, edges shorter
      final t      = (i / (count - 1)) * 2 - 1; // -1 … +1
      final env    = 1.0 - t * t * 0.45;
      return (env * (0.35 + rng.nextDouble() * 0.65)).clamp(0.08, 1.0);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 55;
    const gap      = 2.5;
    final barW     = (size.width - (barCount - 1) * gap) / barCount;
    final maxH     = size.height;
    final progressX = progress * size.width;

    // Build heights lazily — cached for the lifetime of this key
    final cacheKey  = Object.hashAll([size.width.round(), barCount]);
    final heights   = _WaveformPainter._heightCache.putIfAbsent(
      ValueKey(cacheKey),
      () => _buildHeights(cacheKey, barCount),
    );

    final activePaint   = Paint()..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final x       = i * (barW + gap);
      final barH    = heights[i] * maxH;
      final y       = (maxH - barH) / 2;
      final midX    = x + barW / 2;
      final isActive = midX <= progressX;

      if (isActive) {
        // Gradient from accent → bright as bar fills
        activePaint.color = Color.lerp(
          activeColor.withAlpha(0xCC),
          activeColor,
          midX / size.width,
        )!;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          const Radius.circular(2),
        ),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      progress != old.progress || activeColor != old.activeColor;
}
