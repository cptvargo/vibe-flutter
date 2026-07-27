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
import '../theme/ambient_theme.dart';
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
  StreamSubscription<MediaItem?>? _completionSub;
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
      // Dismiss the player when the queue empties naturally (last track ended).
      // mediaItem becomes null exactly when _onTrackNaturalEnd clears the queue.
      _completionSub = handler.mediaItem.listen((item) {
        if (item == null && mounted) _animateDismiss();
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
    final theme     = ref.watch(playerThemeProvider);
    final ambient   = ref.watch(ambientThemeProvider);
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
                return _Body(handler: handler, item: item, theme: theme, ambient: ambient);
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
  final AmbientTheme     ambient;

  const _Body({
    required this.handler,
    required this.item,
    required this.theme,
    required this.ambient,
  });

  @override
  Widget build(BuildContext context) {
    final artUrl = item.artUri?.toString();

    return Scaffold(
      backgroundColor: Colors.black,
      body: TweenAnimationBuilder<AmbientTheme>(
        tween: _AmbientTween(end: ambient),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOut,
        builder: (context, animAmbient, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _AmbientBackground(ambient: animAmbient, artUrl: artUrl),
              SafeArea(
                child: _Content(
                  handler: handler,
                  item: item,
                  theme: theme,
                  ambient: animAmbient,
                  artUrl: artUrl,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Smooth ambient theme tween ──────────────────────────────────────────────
class _AmbientTween extends Tween<AmbientTheme> {
  _AmbientTween({AmbientTheme? begin, required AmbientTheme end})
      : super(begin: begin ?? end, end: end);

  @override
  AmbientTheme lerp(double t) => AmbientTheme.lerp(begin!, end!, t);
}

// ── Layered ambient background with breathing glow ──────────────────────────
class _AmbientBackground extends StatefulWidget {
  final AmbientTheme ambient;
  final String?      artUrl;

  const _AmbientBackground({required this.ambient, required this.artUrl});

  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathCtrl;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breathCtrl,
      builder: (context, _) {
        final t    = _breathCtrl.value; // 0.0 → 1.0
        final glow = widget.ambient.glowColor; // pure color, full alpha — we control opacity

        // Three-layer lighting model that simulates physical light emanating from artwork.
        //
        // Layer 1 — CORE: tight, very bright, breathing.
        //   Non-linear stops mimic inverse-square light falloff: stays intense near
        //   the source (art), drops off sharply before reaching corners.
        //   Center peaks 75–100% of full saturation with each breath.
        final coreCenter = (255 * (0.75 + 0.25 * t)).round(); // 191 → 255
        final coreMid    = (105 * (0.65 + 0.35 * t)).round(); // 68 → 105  (at 40% stop)

        // Layer 2 — HALO: medium width, subtle breath.
        //   Creates the atmospheric spread that makes the glow feel like it fills the room.
        final haloCenter = (80  * (0.70 + 0.30 * t)).round(); // 56 → 80

        return Stack(
          fit: StackFit.expand,
          children: [
            // Absolute black base — pure palette atmosphere, not bleed from the bg
            const ColoredBox(color: Colors.black),

            // Blurred art at 12% — barely visible texture; does NOT define the atmosphere.
            // The palette-generated gradients do that.
            if (widget.artUrl != null)
              Opacity(
                opacity: 0.12,
                child: CachedNetworkImage(
                  imageUrl: widget.artUrl!,
                  fit: BoxFit.cover,
                  imageBuilder: (_, imageProvider) => ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: Image(
                      image: imageProvider,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget:  (_, _, _) => const SizedBox.shrink(),
                ),
              ),

            // Scrim on blurred art — ensures it recedes and never competes with the glow
            const ColoredBox(color: Color(0x77000000)),

            // ── LAYER 1: Core glow ──────────────────────────────────────────────────
            // Tight radius (0.78 × shortest_side) centered on artwork.
            // Three-stop non-linear falloff: stays saturated until 40% of radius,
            // then drops steeply — this is what makes corners go fully dark.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.20),
                  radius: 0.78,
                  colors: [
                    glow.withAlpha(coreCenter),
                    glow.withAlpha(coreMid),
                    glow.withAlpha(0),
                  ],
                  stops: const [0.0, 0.40, 1.0],
                ),
              ),
            ),

            // ── LAYER 2: Atmospheric halo ───────────────────────────────────────────
            // Wider, softer — provides the ambient spread to screen edges at the art level.
            // Breathing is slower and subtler than the core.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.08),
                  radius: 1.10,
                  colors: [glow.withAlpha(haloCenter), glow.withAlpha(0)],
                ),
              ),
            ),

            // ── LAYER 3: Edge ambiance ──────────────────────────────────────────────
            // Very wide, very soft — the "room fill" that gives physical presence.
            // Static (no breathing) for smooth, natural ambient light feel.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.02),
                  radius: 1.60,
                  colors: [glow.withAlpha(0x28), glow.withAlpha(0)],
                ),
              ),
            ),

            // ── VIGNETTE: Heavy bottom darkening ────────────────────────────────────
            // Controls live in near-black — strong chiaroscuro between lit art
            // and functional controls. This contrast IS the premium feel.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC000000),
                    Colors.black,
                  ],
                  stops: [0.0, 0.25, 0.52, 0.78],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Main content column ─────────────────────────────────────────────────────
class _Content extends ConsumerWidget {
  final VibeAudioHandler handler;
  final MediaItem        item;
  final VibeTheme        theme;
  final AmbientTheme     ambient;
  final String?          artUrl;

  const _Content({
    required this.handler,
    required this.item,
    required this.theme,
    required this.ambient,
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
    final palette  = _GlassButtonPalette.from(ambient);

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
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer atmospheric bloom — wide soft halo, artwork as light source
                      Container(
                        width: size * 1.85,
                        height: size * 1.85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              ambient.playButtonColor.withAlpha(0x44),
                              ambient.playButtonColor.withAlpha(0),
                            ],
                            stops: const [0.3, 1.0],
                          ),
                        ),
                      ),
                      // Inner tight bloom — bright aura hugging the art edges
                      Container(
                        width: size * 1.18,
                        height: size * 1.18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              ambient.playButtonColor.withAlpha(0x77),
                              ambient.playButtonColor.withAlpha(0),
                            ],
                            stops: const [0.35, 1.0],
                          ),
                        ),
                      ),
                      // Album art with depth shadows
                      Container(
                        width: size, height: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: ambient.playButtonColor.withAlpha(0x66),
                              blurRadius: 60,
                              spreadRadius: 6,
                              offset: const Offset(0, 20),
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
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),

        // Controls panel — subtly elevated surface in the dark zone below the art.
        // The rounded top + dark fill creates a physical separation from the glow.
        Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            color: Color(0x1A000000),
          ),
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
          child: StreamBuilder<PlaybackState>(
            stream: handler.playbackState,
            builder: (context, statSnap) {
              final isPlaying = statSnap.data?.playing ?? false;
              return StreamBuilder<Duration>(
                stream: handler.positionStream,
                builder: (context, posSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = handler.duration
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
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    shadows: [
                                      Shadow(
                                        color: ambient.playButtonColor.withAlpha(0x55),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ambient.waveformActive,
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
                        activeColor:    ambient.playButtonColor,
                        activeColorEnd: ambient.waveformActive,
                        inactiveColor:  ambient.waveformInactive,
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
                          _GlassTransportButton(
                            icon: Icons.skip_previous_rounded,
                            size: 54, iconSize: 28,
                            intensity: 0.65,
                            palette: palette,
                            onTap: handler.skipToPrevious,
                          ),
                          _GlassTransportButton(
                            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 72, iconSize: 38,
                            intensity: 1.0,
                            palette: palette,
                            onTap: () => isPlaying ? handler.pause() : handler.play(),
                          ),
                          _GlassTransportButton(
                            icon: Icons.skip_next_rounded,
                            size: 54, iconSize: 28,
                            intensity: 0.65,
                            palette: palette,
                            onTap: handler.skipToNext,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Secondary: shuffle / repeat / queue
                      _SecondaryControls(handler: handler, theme: theme, palette: palette),
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
  final VibeAudioHandler    handler;
  final VibeTheme           theme;
  final _GlassButtonPalette palette;
  const _SecondaryControls({
    required this.handler,
    required this.theme,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: handler.shuffleModeEnabledStream,
      builder: (context, shuffleSnap) {
        final shuffleOn = shuffleSnap.data ?? false;
        return StreamBuilder<LoopMode>(
          stream: handler.loopModeStream,
          builder: (context, loopSnap) {
            final loop = loopSnap.data ?? LoopMode.off;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _GlassTransportButton(
                  icon: Icons.shuffle_rounded,
                  size: 44, iconSize: 20,
                  intensity: 0.45,
                  palette: palette,
                  active:  shuffleOn,
                  onTap: () => handler.setShuffleMode(
                    shuffleOn
                        ? AudioServiceShuffleMode.none
                        : AudioServiceShuffleMode.all,
                  ),
                ),
                _GlassTransportButton(
                  icon: loop == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  size: 44, iconSize: 20,
                  intensity: 0.45,
                  palette: palette,
                  active:  loop != LoopMode.off,
                  onTap: () {
                    final next = switch (loop) {
                      LoopMode.off => AudioServiceRepeatMode.all,
                      LoopMode.all => AudioServiceRepeatMode.one,
                      _            => AudioServiceRepeatMode.none,
                    };
                    handler.setRepeatMode(next);
                  },
                ),
                _GlassTransportButton(
                  icon: Icons.queue_music_rounded,
                  size: 44, iconSize: 20,
                  intensity: 0.45,
                  palette: palette,
                  onTap: () => showModalBottomSheet(
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
            stream: handler.currentIndexStream,
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

// ── Glass button palette ─────────────────────────────────────────────────────
// Three-tone color set from AmbientTheme. Using three distinct tones instead of
// one color is what makes the glass read as a colored crystal rather than a tint.
//   core      = vibrant (deepest, most saturated hue — the primary light source)
//   mid       = interpolated midpoint (interior depth / color transition)
//   highlight = lightVibrant (surface brightness, rim catch, wide glow)
class _GlassButtonPalette {
  final Color core;
  final Color mid;
  final Color highlight;

  const _GlassButtonPalette({
    required this.core,
    required this.mid,
    required this.highlight,
  });

  factory _GlassButtonPalette.from(AmbientTheme a) => _GlassButtonPalette(
    core:      a.playButtonColor,
    mid:       Color.lerp(a.playButtonColor, a.waveformActive, 0.50)!,
    highlight: a.waveformActive,
  );
}

// ── Glass transport button ──────────────────────────────────────────────────
// Unified material for all playback controls. 6-layer compositing model:
//   1. Room glow    — 3 BoxShadow halos in core / mid / highlight (distinct tones)
//   2. Glass body   — BackdropFilter blur: the material itself
//   3. Illumination — 5-stop RadialGradient: highlight → core → blend → mid
//   4. Specular     — white crescent at upper third (convex lens reflection)
//   5. Inner shadow — lower hemisphere darkening (lens thickness / depth)
//   6. Icon
//
// [intensity] scales all optical parameters: 0.45 = secondary, 0.65 = skip, 1.0 = play.
// [active]    shifts illumination toward highlight, making the state unmistakable.
class _GlassTransportButton extends StatelessWidget {
  final IconData            icon;
  final double              size;
  final double              iconSize;
  final double              intensity;
  final _GlassButtonPalette palette;
  final bool                active;
  final VoidCallback?       onTap;

  const _GlassTransportButton({
    required this.icon,
    required this.palette,
    this.size      = 48,
    this.iconSize  = 22,
    this.intensity = 0.65,
    this.active    = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Active: inner core shifts toward highlight (brighter, lighter hue).
    // This makes active shuffle/repeat glow distinctly without changing the palette.
    final Color illumInner = active
        ? Color.lerp(palette.highlight, Colors.white, 0.20)!
        : Color.lerp(palette.highlight, palette.core,  0.30)!;
    final Color illumCore  = active ? palette.highlight : palette.core;
    final Color illumBlend = Color.lerp(palette.core, palette.mid, 0.50)!;
    final Color glowLead   = active ? palette.highlight : palette.core;

    // Icon is near-white with a subtle palette tint — stays readable at any size.
    // Active: fully highlight-colored so the state reads without needing the icon label.
    final Color iconColor = active
        ? palette.highlight
        : Color.lerp(Colors.white, palette.highlight, 0.15)!;

    // Opacity values all scale linearly with intensity.
    // Room glow
    final int gA1  = (0x40 * intensity).round().clamp(0, 255); // core halo — tight
    final int gA2  = (0x29 * intensity).round().clamp(0, 255); // mid halo
    final int gA3  = (0x14 * intensity).round().clamp(0, 255); // highlight halo — wide
    // Internal illumination — 4 alpha stops across 5 color stops
    final int ilA1 = (0xE6 * intensity).round().clamp(0, 255); // 90% — inner bright core
    final int ilA2 = (0xB3 * intensity).round().clamp(0, 255); // 70% — primary color band
    final int ilA3 = (0x73 * intensity).round().clamp(0, 255); // 45% — blend transition
    final int ilA4 = (0x33 * intensity).round().clamp(0, 255); // 20% — outer edge fade
    // Specular
    final int spA1 = (0x59 * intensity).round().clamp(0, 255); // 35% — crescent center
    final int spA2 = (0x1E * intensity).round().clamp(0, 255); // 12% — crescent edge

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [

          // ── Layer 1: Room glow ──────────────────────────────────────────
          // Each BoxShadow uses a DIFFERENT palette color at a different radius.
          // core (tight) bleeds into the scene first; highlight (wide) fills the room.
          // Three concentric halos in three tones = the glow reads as chromatic light,
          // not a single-color circle.
          SizedBox(
            width: size, height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                boxShadow: [
                  BoxShadow(
                    color: glowLead.withAlpha(gA1),
                    blurRadius: 34 * intensity,
                    spreadRadius: 2 * intensity,
                  ),
                  BoxShadow(
                    color: palette.mid.withAlpha(gA2),
                    blurRadius: 72 * intensity,
                    spreadRadius: 12 * intensity,
                  ),
                  BoxShadow(
                    color: palette.highlight.withAlpha(gA3),
                    blurRadius: 120 * intensity,
                    spreadRadius: 26 * intensity,
                  ),
                ],
              ),
            ),
          ),

          // ── Layer 2: Glass body ─────────────────────────────────────────
          // BackdropFilter samples the ambient scene behind this button —
          // the three-layer ambient glow and blurred artwork color.
          // The glass literally contains the room's light: not painted, sampled.
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(0x0D),   // 5% tint — glass is transparent
                  border: Border.all(
                    color: Colors.white.withAlpha(0x2E), // 18% rim
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 3: Internal illumination ──────────────────────────────
          // Five color stops blend illumInner → illumCore → illumBlend → mid → transparent.
          // The center is the brightest and most mixed (near-white blended with highlight).
          // Moving outward, the gradient passes through core → blend → mid before fading.
          // At any given album, THREE DISTINCT TONES are visible simultaneously inside
          // the glass — this is the difference between a tinted circle and a crystal lens.
          IgnorePointer(
            child: SizedBox(
              width: size, height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(0.0, 0.18),
                    radius: 0.95,
                    colors: [
                      illumInner.withAlpha(ilA1),
                      illumCore.withAlpha(ilA2),
                      illumBlend.withAlpha(ilA3),
                      palette.mid.withAlpha(ilA4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.28, 0.55, 0.80, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 4: Specular highlight ─────────────────────────────────
          // Origin at Alignment(0, -2.4) — far above the button — sweeps a
          // crescent arc across the upper third. Physically correct for a convex lens.
          IgnorePointer(
            child: SizedBox(
              width: size, height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -2.4),
                    radius: 2.10,
                    colors: [
                      Colors.white.withAlpha(spA1),
                      Colors.white.withAlpha(spA2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 5: Inner shadow ────────────────────────────────────────
          // Rear face of the lens in shadow — implies thickness, creates depth.
          IgnorePointer(
            child: SizedBox(
              width: size, height: size,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x22000000)],
                    stops: [0.40, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 6: Icon ────────────────────────────────────────────────
          Icon(icon, color: iconColor, size: iconSize),
        ],
      ),
    );
  }
}

// ── Waveform seek bar ───────────────────────────────────────────────────────
class _WaveformSeekBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final String trackId;
  final Color  activeColor;
  final Color  activeColorEnd;
  final Color  inactiveColor;
  final ValueChanged<double> onSeek; // emits ratio 0.0 – 1.0

  const _WaveformSeekBar({
    required this.progress,
    required this.trackId,
    required this.activeColor,
    required this.activeColorEnd,
    required this.inactiveColor,
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
            progress:       progress,
            activeColor:    activeColor,
            activeColorEnd: activeColorEnd,
            inactiveColor:  inactiveColor,
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
  final Color  activeColorEnd;
  final Color  inactiveColor;

  // Heights shared across repaints via the ValueKey — set once per track
  static final Map<Key, List<double>> _heightCache = {};

  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.activeColorEnd,
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
        // Two-color palette gradient: vibrant at left → lightVibrant at right.
        // Connects the waveform visually to the ambient lighting and artwork.
        activePaint.color = Color.lerp(activeColor, activeColorEnd, midX / size.width)!;
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
      progress != old.progress ||
      activeColor    != old.activeColor ||
      activeColorEnd != old.activeColorEnd;
}
