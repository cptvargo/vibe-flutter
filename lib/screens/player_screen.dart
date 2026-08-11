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
  StreamSubscription<MediaItem?>? _mediaItemSub;
  MediaItem? _lastItem;
  bool _queueLoaded           = false;
  bool _nearingEnd            = false;
  bool _crossedEarlyThreshold = false;
  String? _nearingEndTrackId;
  Timer? _queueEndTimer;
  StateController<bool>? _playerOpenCtrl;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _playerOpenCtrl = ref.read(playerOpenProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final handler = ref.read(audioHandlerProvider);

      _mediaItemSub = handler.mediaItem.listen((item) {
        if (item != null) {
          _lastItem              = item;
          _queueLoaded           = true;
          _nearingEnd            = false;
          _nearingEndTrackId     = null;
          _crossedEarlyThreshold = false;
          _queueEndTimer?.cancel();
        } else if (_queueLoaded && _nearingEnd && _nearingEndTrackId == _lastItem?.id) {
          // Queue ended naturally: position was genuinely past 90% of this
          // specific track, not a stale value from a previous session.
          _queueEndTimer?.cancel();
          _queueEndTimer = Timer(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            if (handler.mediaItem.value != null) return;
            _animateDismiss();
          });
        }
      });

      // Only set _nearingEnd once position has been seen below 80% for the
      // current track — prevents stale end-of-track position from a prior
      // play session from triggering dismiss on a freshly loaded track.
      handler.positionStream.listen((pos) {
        final dur = handler.duration;
        if (dur == null || dur.inMilliseconds == 0) return;
        final pct = pos.inMilliseconds / dur.inMilliseconds;
        if (pct < 0.80) {
          _crossedEarlyThreshold = true;
          if (_nearingEnd) {
            _nearingEnd        = false;
            _nearingEndTrackId = null;
          }
        } else if (pct > 0.90 && _crossedEarlyThreshold && !_nearingEnd) {
          _nearingEnd        = true;
          _nearingEndTrackId = _lastItem?.id;
        }
      });
    });
  }

  @override
  void dispose() {
    _mediaItemSub?.cancel();
    _queueEndTimer?.cancel();
    _snapCtrl.dispose();
    _playerOpenCtrl?.state = false;
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
                // Fall back to _lastItem during brief null transitions (queue setup,
                // track swaps). Only show black if we've never seen any item.
                final item = snap.data ?? _lastItem;
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
                        colorAnchor: ambient.waveformAnchor,
                        colorMid:    ambient.playButtonColor,
                        colorEnd:    ambient.waveformActive,
                        colorTail:   ambient.waveformTail,
                        inactiveColor: ambient.waveformInactive,
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

                      // Single transport row: shuffle | prev | play | next | repeat
                      // Prev/next/shuffle/repeat are bare icons (Spotify-style).
                      // Only the play button keeps the glass material.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          StreamBuilder<bool>(
                            stream: handler.shuffleModeEnabledStream,
                            builder: (_, snap) {
                              final on = snap.data ?? false;
                              return _PlainIconButton(
                                icon: Icons.shuffle_rounded,
                                iconSize: 22,
                                active: on,
                                inactiveColor: Color.lerp(Colors.white, ambient.waveformActive, 0.08)!.withAlpha(0xBB),
                                activeColor: ambient.waveformActive,
                                onTap: () => handler.setShuffleMode(
                                  on ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                                ),
                              );
                            },
                          ),
                          _PlainIconButton(
                            icon: Icons.skip_previous_rounded,
                            iconSize: 30,
                            inactiveColor: Colors.white.withAlpha(0xDD),
                            activeColor: ambient.waveformActive,
                            onTap: handler.skipToPrevious,
                          ),
                          _GlassTransportButton(
                            icon: Icons.play_arrow_rounded,
                            size: 72, iconSize: 34,
                            intensity: 1.0,
                            palette: palette,
                            customIcon: isPlaying ? const _ThinPauseIcon(height: 20) : null,
                            onTap: () => isPlaying ? handler.pause() : handler.play(),
                          ),
                          _PlainIconButton(
                            icon: Icons.skip_next_rounded,
                            iconSize: 30,
                            inactiveColor: Colors.white.withAlpha(0xDD),
                            activeColor: ambient.waveformActive,
                            onTap: handler.skipToNext,
                          ),
                          StreamBuilder<LoopMode>(
                            stream: handler.loopModeStream,
                            builder: (_, snap) {
                              final loop = snap.data ?? LoopMode.off;
                              return _PlainIconButton(
                                icon: loop == LoopMode.one
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                iconSize: 22,
                                active: loop != LoopMode.off,
                                inactiveColor: Color.lerp(Colors.white, ambient.waveformActive, 0.08)!.withAlpha(0xBB),
                                activeColor: ambient.waveformActive,
                                onTap: () => handler.setRepeatMode(switch (loop) {
                                  LoopMode.off => AudioServiceRepeatMode.all,
                                  LoopMode.all => AudioServiceRepeatMode.one,
                                  _            => AudioServiceRepeatMode.none,
                                }),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Queue icon — right-aligned below transport
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

// ── Queue button row (right-aligned, below transport) ───────────────────────
class _SecondaryControls extends StatelessWidget {
  final VibeAudioHandler handler;
  final VibeTheme        theme;

  const _SecondaryControls({required this.handler, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.queue_music_rounded,
              color: Colors.white.withAlpha(0x77), size: 22),
          onPressed: () => showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _QueueSheet(handler: handler, theme: theme),
          ),
        ),
      ],
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
                              ? _AnimatedEqualizer(color: theme.accentBright)
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

// ── Animated equalizer — now-playing indicator in queue list ────────────────
class _AnimatedEqualizer extends StatefulWidget {
  final Color color;
  const _AnimatedEqualizer({required this.color});
  @override
  State<_AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<_AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t  = _ctrl.value * 2 * pi;
        final h1 = 3 + 11 * ((sin(t * 1.10)       + 1) / 2);
        final h2 = 3 + 11 * ((sin(t * 0.85 + 1.0) + 1) / 2);
        final h3 = 3 + 11 * ((sin(t * 1.30 + 2.1) + 1) / 2);
        return SizedBox(
          width: 16, height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [_bar(h1), _bar(h2), _bar(h3)],
          ),
        );
      },
    );
  }

  Widget _bar(double h) => Container(
    width: 3, height: h,
    decoration: BoxDecoration(
      color: widget.color,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );
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

// ── Album-gradient play button ──────────────────────────────────────────────
// Bold, album-driven color button. The album IS the button.
// 4-layer model:
//   1. Room glow    — 3 BoxShadow halos (core / mid / highlight)
//   2. Gradient body — diagonal LinearGradient: highlight → core → deep anchor
//   3. Center bloom  — radial white overlay for perceived depth / lit-from-within
//   4. Bottom shadow — subtle darkening for volume
//   5. Icon          — pure white, crisp
class _GlassTransportButton extends StatelessWidget {
  final IconData            icon;
  final double              size;
  final double              iconSize;
  final double              intensity;
  final _GlassButtonPalette palette;
  final Widget?             customIcon;
  final VoidCallback?       onTap;

  const _GlassTransportButton({
    required this.icon,
    required this.palette,
    this.size       = 48,
    this.iconSize   = 22,
    this.intensity  = 0.65,
    this.customIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Deep anchor: darkens palette toward black for gradient contrast at edge
    final Color dark = Color.lerp(palette.core, Colors.black, 0.42)!;

    // Room glow halos — three palette tones at expanding radii
    final int gA1 = (0x55 * intensity).round().clamp(0, 255);
    final int gA2 = (0x33 * intensity).round().clamp(0, 255);
    final int gA3 = (0x1A * intensity).round().clamp(0, 255);

    // Gradient circle slightly inset from tap target — breathing room around icon
    final double gradSize = size * 0.62;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size, height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [

            // ── Room glow ───────────────────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  boxShadow: [
                    BoxShadow(
                      color: palette.core.withAlpha(gA1),
                      blurRadius: 34 * intensity,
                      spreadRadius: 2  * intensity,
                    ),
                    BoxShadow(
                      color: palette.mid.withAlpha(gA2),
                      blurRadius: 72  * intensity,
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

            // ── Gradient body ────────────────────────────────────────────
            // Diagonal sweep: lightVibrant (top-left) → vibrant → deep anchor (bottom-right).
            // Three distinct palette tones — every album produces a unique combination.
            SizedBox(
              width: gradSize, height: gradSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: const Alignment(-0.9, -0.9),
                    end:   const Alignment( 0.9,  0.9),
                    colors: [palette.highlight, palette.core, dark],
                    stops: const [0.0, 0.46, 1.0],
                  ),
                ),
              ),
            ),

            // ── Center bloom ─────────────────────────────────────────────
            // Soft white at center creates a "lit from within" depth — the button
            // reads as a light source, not a flat disc.
            IgnorePointer(
              child: SizedBox(
                width: gradSize, height: gradSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      radius: 0.60,
                      colors: [Colors.white.withAlpha(0x38), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom depth shadow ──────────────────────────────────────
            // Darkens the lower edge to give the button perceived curvature.
            IgnorePointer(
              child: SizedBox(
                width: gradSize, height: gradSize,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x44000000)],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // ── Icon ─────────────────────────────────────────────────────
            customIcon ?? Icon(icon, color: Colors.white, size: iconSize),
          ],
        ),
      ),
    );
  }
}

// ── Thin pause bars ─────────────────────────────────────────────────────────
// Custom pause icon with slim rounded bars — thinner than any Material icon.
class _ThinPauseIcon extends StatelessWidget {
  final double height;
  const _ThinPauseIcon({this.height = 20});

  @override
  Widget build(BuildContext context) {
    final barW = (height * 0.16).clamp(2.5, 4.0);
    final gap  = height * 0.30;
    final radius = Radius.circular(barW / 2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: barW, height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(radius),
          ),
        ),
        SizedBox(width: gap),
        Container(
          width: barW, height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(radius),
          ),
        ),
      ],
    );
  }
}

// ── Plain icon button (no glass) ────────────────────────────────────────────
// Used for prev, next, shuffle, repeat — Spotify-style: bare icon, no circle.
// Inactive: near-white with a subtle palette tint so icons feel "of" the album.
// Active:   full waveformActive (lightVibrant) — state is unmistakable.
class _PlainIconButton extends StatelessWidget {
  final IconData      icon;
  final double        iconSize;
  final bool          active;
  final Color         inactiveColor;
  final Color         activeColor;
  final VoidCallback? onTap;

  const _PlainIconButton({
    required this.icon,
    required this.inactiveColor,
    required this.activeColor,
    this.iconSize = 26,
    this.active   = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: iconSize,
            color: active ? activeColor : inactiveColor),
      ),
    );
  }
}

// ── Waveform seek bar ───────────────────────────────────────────────────────
class _WaveformSeekBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final String trackId;
  final Color  colorAnchor;   // darkVibrant  — deep start
  final Color  colorMid;      // vibrant      — main energy
  final Color  colorEnd;      // lightVibrant — bright bloom
  final Color  colorTail;     // muted        — soft resolution
  final Color  inactiveColor;
  final ValueChanged<double> onSeek;

  const _WaveformSeekBar({
    required this.progress,
    required this.trackId,
    required this.colorAnchor,
    required this.colorMid,
    required this.colorEnd,
    required this.colorTail,
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
            progress:     progress,
            colorAnchor:  colorAnchor,
            colorMid:     colorMid,
            colorEnd:     colorEnd,
            colorTail:    colorTail,
            inactiveColor: inactiveColor,
          ),
          key: ValueKey(trackId),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color  colorAnchor;  // darkVibrant — deep start
  final Color  colorMid;     // vibrant — main energy
  final Color  colorEnd;     // lightVibrant — bright bloom
  final Color  colorTail;    // muted — soft resolution
  final Color  inactiveColor;

  static final Map<Key, List<double>> _heightCache = {};

  const _WaveformPainter({
    required this.progress,
    required this.colorAnchor,
    required this.colorMid,
    required this.colorEnd,
    required this.colorTail,
    required this.inactiveColor,
  });

  static List<double> _buildHeights(int seed, int count) {
    final rng = Random(seed);
    return List.generate(count, (i) {
      final t   = (i / (count - 1)) * 2 - 1;
      final env = 1.0 - t * t * 0.45;
      return (env * (0.35 + rng.nextDouble() * 0.65)).clamp(0.08, 1.0);
    });
  }

  // 4-stop gradient: anchor → mid → end → tail, mapped across 0.0–1.0
  Color _gradientAt(double t) {
    if (t < 0.33) {
      return Color.lerp(colorAnchor, colorMid, t / 0.33)!;
    } else if (t < 0.67) {
      return Color.lerp(colorMid, colorEnd, (t - 0.33) / 0.34)!;
    } else {
      return Color.lerp(colorEnd, colorTail, (t - 0.67) / 0.33)!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const barCount  = 55;
    const gap       = 2.5;
    final barW      = (size.width - (barCount - 1) * gap) / barCount;
    final maxH      = size.height;
    final progressX = progress * size.width;

    final cacheKey = Object.hashAll([size.width.round(), barCount]);
    final heights  = _WaveformPainter._heightCache.putIfAbsent(
      ValueKey(cacheKey),
      () => _buildHeights(cacheKey, barCount),
    );

    final activePaint   = Paint()..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final x        = i * (barW + gap);
      final barH     = heights[i] * maxH;
      final y        = (maxH - barH) / 2;
      final midX     = x + barW / 2;
      final isActive = midX <= progressX;

      if (isActive) {
        // 4-stop palette gradient gives each album a color fingerprint.
        // Height-based brightness: tall bars (loud moments) pull ~14% toward white —
        // the waveform shape of each track becomes visually encoded in the color.
        final base = _gradientAt(midX / size.width);
        activePaint.color = Color.lerp(base, Colors.white, heights[i] * 0.14)!;
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
      progress     != old.progress     ||
      colorAnchor  != old.colorAnchor  ||
      colorMid     != old.colorMid     ||
      colorEnd     != old.colorEnd     ||
      colorTail    != old.colorTail;
}

