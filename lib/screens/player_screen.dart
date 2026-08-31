import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _kTopBarH        = 56.0;   // drag handle + options row
const _kControlsPanelH = 268.0;
const _kQueueHintH     = 48.0;   // "ViBE Queue" pull-up strip below controls
const _kCompactHeaderH  = 80.0;
const _kArtCompact      = 56.0;
const _kArtCompactLeft  = 16.0;

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
    with TickerProviderStateMixin {
  double _dragOffset = 0;
  late final AnimationController _snapCtrl;
  late final AnimationController _expansion; // 0 = full player, 1 = compact+queue
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
    _expansion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
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
          _queueEndTimer?.cancel();
          _queueEndTimer = Timer(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            if (handler.mediaItem.value != null) return;
            _animateDismiss();
          });
        }
      });

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
    _expansion.dispose();
    _playerOpenCtrl?.state = false;
    super.dispose();
  }

  void _animateDismiss() {
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
    final dy = d.delta.dy;
    final screenH = MediaQuery.of(context).size.height;
    if (_expansion.value > 0) {
      _expansion.value = (_expansion.value - dy / (screenH * 0.45)).clamp(0.0, 1.0);
      return;
    }
    if (dy < 0 && _dragOffset == 0) {
      _expansion.value = (-dy / (screenH * 0.45)).clamp(0.0, 1.0);
      return;
    }
    if (dy > 0 || _dragOffset > 0) {
      setState(() => _dragOffset = (_dragOffset + dy).clamp(0.0, double.infinity));
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_expansion.value > 0) {
      double target;
      if (velocity < -400) {
        target = 1.0;
      } else if (velocity > 400) {
        target = 0.0;
      } else {
        target = _expansion.value >= 0.45 ? 1.0 : 0.0;
      }
      _expansion.animateTo(target,
          curve: Curves.easeOutCubic,
          duration: const Duration(milliseconds: 320));
      return;
    }
    final screenH = MediaQuery.of(context).size.height;
    if (velocity > 500 || _dragOffset > screenH * 0.28) {
      _animateDismiss();
    } else {
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

  void _onCompactHeaderDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy > 0) {
      final screenH = MediaQuery.of(context).size.height;
      _expansion.value =
          (_expansion.value - d.delta.dy / (screenH * 0.45)).clamp(0.0, 1.0);
    }
  }

  void _onCompactHeaderDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final snapTo = velocity > 300 || _expansion.value < 0.5 ? 0.0 : 1.0;
    _expansion.animateTo(snapTo,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 320));
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final theme   = ref.watch(playerThemeProvider);
    final ambient = ref.watch(ambientThemeProvider);

    return AnimatedBuilder(
      animation: _expansion,
      builder: (context, child) {
        final screenH      = MediaQuery.of(context).size.height;
        final revealT      = (_dragOffset / screenH).clamp(0.0, 1.0);
        final barrierAlpha = ((1.0 - revealT) * 0x99).round();
        final queueOpen    = _expansion.value >= 0.95;

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withAlpha(barrierAlpha)),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: queueOpen ? null : _onDragUpdate,
                onVerticalDragEnd:    queueOpen ? null : _onDragEnd,
                child: child,
              ),
            ),
          ],
        );
      },
      child: StreamBuilder<MediaItem?>(
        stream: ref.read(audioHandlerProvider).mediaItem,
        builder: (context, snap) {
          final item = snap.data ?? _lastItem;
          if (item == null) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: const SizedBox.expand(),
            );
          }
          return _Body(
            handler:                    handler,
            item:                       item,
            theme:                      theme,
            ambient:                    ambient,
            expansion:                  _expansion,
            onCompactHeaderDragUpdate:  _onCompactHeaderDragUpdate,
            onCompactHeaderDragEnd:     _onCompactHeaderDragEnd,
          );
        },
      ),
    );
  }
}

// ── Background + safe-area wrapper ─────────────────────────────────────────
class _Body extends StatelessWidget {
  final VibeAudioHandler          handler;
  final MediaItem                 item;
  final VibeTheme                 theme;
  final AmbientTheme              ambient;
  final AnimationController       expansion;
  final GestureDragUpdateCallback onCompactHeaderDragUpdate;
  final GestureDragEndCallback    onCompactHeaderDragEnd;

  const _Body({
    required this.handler,
    required this.item,
    required this.theme,
    required this.ambient,
    required this.expansion,
    required this.onCompactHeaderDragUpdate,
    required this.onCompactHeaderDragEnd,
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
                  handler:                   handler,
                  item:                      item,
                  theme:                     theme,
                  ambient:                   animAmbient,
                  artUrl:                    artUrl,
                  expansion:                 expansion,
                  onCompactHeaderDragUpdate: onCompactHeaderDragUpdate,
                  onCompactHeaderDragEnd:    onCompactHeaderDragEnd,
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
        final t    = _breathCtrl.value;
        final glow = widget.ambient.glowColor;

        final coreCenter = (255 * (0.75 + 0.25 * t)).round();
        final coreMid    = (105 * (0.65 + 0.35 * t)).round();
        final haloCenter = (80  * (0.70 + 0.30 * t)).round();

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),

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

            const ColoredBox(color: Color(0x77000000)),

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

            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.08),
                  radius: 1.10,
                  colors: [glow.withAlpha(haloCenter), glow.withAlpha(0)],
                ),
              ),
            ),

            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.02),
                  radius: 1.60,
                  colors: [glow.withAlpha(0x28), glow.withAlpha(0)],
                ),
              ),
            ),

            // Softened overlay — lets album color bleed through the bottom half.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    const Color(0x55000000),
                    const Color(0x99000000),
                  ],
                  stops: const [0.0, 0.38, 0.65, 1.0],
                ),
              ),
            ),

            // Album color rises from below into the controls area.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, 1.8),
                  radius: 1.4,
                  colors: [glow.withAlpha(0x99), glow.withAlpha(0)],
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
class _Content extends ConsumerStatefulWidget {
  final VibeAudioHandler          handler;
  final MediaItem                 item;
  final VibeTheme                 theme;
  final AmbientTheme              ambient;
  final String?                   artUrl;
  final AnimationController       expansion;
  final GestureDragUpdateCallback onCompactHeaderDragUpdate;
  final GestureDragEndCallback    onCompactHeaderDragEnd;

  const _Content({
    required this.handler,
    required this.item,
    required this.theme,
    required this.ambient,
    this.artUrl,
    required this.expansion,
    required this.onCompactHeaderDragUpdate,
    required this.onCompactHeaderDragEnd,
  });

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  late final ScrollController _scrollCtrl;

  // Per-slot haptic tracking during queue reorder drag.
  static const _kQueueItemH = 64.0; // vertical: 10 padding + 44 art + 10 padding
  double? _reorderStartY;
  int?    _reorderStartIndex;
  int?    _lastHapticSlot;
  double? _lastPointerY; // updated by Listener so onReorderStart can read it

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onReorderPointerMove(PointerMoveEvent e) {
    _lastPointerY = e.position.dy;
    if (_reorderStartIndex == null || _reorderStartY == null) return;
    final dy      = e.position.dy - _reorderStartY!;
    final slot    = (_reorderStartIndex! + (dy / _kQueueItemH).round()).clamp(0, 200);
    if (slot != _lastHapticSlot) {
      _lastHapticSlot = slot;
      HapticFeedback.selectionClick();
    }
  }

  void _clearReorderState() {
    _reorderStartY     = null;
    _reorderStartIndex = null;
    _lastHapticSlot    = null;
  }

  void _showOptions(BuildContext context) {
    final item     = widget.item;
    final albumId  = item.extras?['albumId']  as String?;
    final artistId = item.extras?['artistId'] as String?;
    final router   = GoRouter.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: false,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: widget.theme.surface,
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
                  colorFilter: ColorFilter.mode(widget.theme.accentBright, BlendMode.srcIn),
                ),
                title: Text('Go to Album',
                    style: TextStyle(color: widget.theme.textColor)),
                onTap: () {
                  Navigator.pop(sheetCtx);
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
                  colorFilter: ColorFilter.mode(widget.theme.accentBright, BlendMode.srcIn),
                ),
                title: Text('Go to Artist',
                    style: TextStyle(color: widget.theme.textColor)),
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

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 48),
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
            icon: Icon(Icons.more_horiz, color: Colors.white.withAlpha(0xBB)),
            onPressed: () => _showOptions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsPanel(
      BuildContext context, bool isFired, _GlassButtonPalette palette) {
    final item    = widget.item;
    final handler = widget.handler;
    final ambient = widget.ambient;

    return Container(
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
              final pos      = posSnap.data ?? Duration.zero;
              final dur      = handler.duration ?? item.duration ?? Duration.zero;
              final progress = dur.inMilliseconds > 0
                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble()
                  : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                              ? const Color(0xFFFF6B1A)
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
                            raw: {},
                          );
                          ref.read(fireMixProvider.notifier).toggle(track);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _WaveformSeekBar(
                    progress:      progress,
                    trackId:       item.id,
                    colorAnchor:   ambient.waveformAnchor,
                    colorMid:      ambient.playButtonColor,
                    colorEnd:      ambient.waveformActive,
                    colorTail:     ambient.waveformTail,
                    inactiveColor: ambient.waveformInactive,
                    onSeek: (ratio) => handler.seek(Duration(
                      milliseconds: (ratio * dur.inMilliseconds).round(),
                    )),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos),
                            style: TextStyle(
                                color: Colors.white.withAlpha(0x88), fontSize: 12)),
                        Text(_fmt(dur),
                            style: TextStyle(
                                color: Colors.white.withAlpha(0x88), fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

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
                            inactiveColor: Colors.white,
                            activeColor: ambient.waveformActive,
                            onTap: () => handler.setShuffleMode(
                              on
                                  ? AudioServiceShuffleMode.none
                                  : AudioServiceShuffleMode.all,
                            ),
                          );
                        },
                      ),
                      _PlainIconButton(
                        icon: Icons.skip_previous_rounded,
                        iconSize: 30,
                        inactiveColor: Colors.white,
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
                        inactiveColor: Colors.white,
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
                            inactiveColor: Colors.white,
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
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildQueueList() {
    final handler = widget.handler;
    final theme   = widget.theme;

    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue,
      builder: (context, queueSnap) {
        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          builder: (context, mediaSnap) {
            final currentId = mediaSnap.data?.id;
            final allTracks = queueSnap.data ?? handler.queue.value;
            final tracks    = allTracks.take(30).toList();

            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: _onReorderPointerMove,
              onPointerUp:     (_) => _clearReorderState(),
              onPointerCancel: (_) => _clearReorderState(),
              child: ReorderableListView.builder(
                scrollController: _scrollCtrl,
                itemCount: tracks.length,
                onReorderStart: (index) {
                  HapticFeedback.mediumImpact();
                  _reorderStartIndex = index;
                  _reorderStartY     = _lastPointerY;
                  _lastHapticSlot    = index;
                },
                onReorderItem: (oldIndex, newIndex) {
                  HapticFeedback.lightImpact();
                  handler.reorderQueue(oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.white.withAlpha(0x10),
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final track     = tracks[index];
                  final isCurrent = track.id == currentId;
                  return _QueueItem(
                    key:       ValueKey('${track.id}_$index'),
                    index:     index,
                    track:     track,
                    isCurrent: isCurrent,
                    theme:     theme,
                    onTap:     () => handler.skipToQueueItem(index),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQueueHint(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.expansion.animateTo(1.0,
          curve: Curves.easeOutCubic,
          duration: const Duration(milliseconds: 320)),
      child: SizedBox(
        height: _kQueueHintH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(0x33),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'ViBE Queue',
              style: TextStyle(
                color: Colors.white.withAlpha(0x66),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fireMix = ref.watch(fireMixProvider);
    final isFired = fireMix.any((t) => t.id == widget.item.id);
    final palette = _GlassButtonPalette.from(widget.ambient);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalH    = constraints.maxHeight;
        final totalW    = constraints.maxWidth;
        final artAreaH  = (totalH - _kTopBarH - _kControlsPanelH - _kQueueHintH)
            .clamp(100.0, double.infinity);
        final artFullSz = min(totalW - 48.0, artAreaH).clamp(100.0, 520.0);
        final artFullL  = (totalW - artFullSz) / 2;
        final artFullT  = _kTopBarH + (artAreaH - artFullSz) / 2;

        return AnimatedBuilder(
                animation: widget.expansion,
                builder: (ctx, _) {
                  final t = widget.expansion.value;
                  const artCompactT = (_kCompactHeaderH - _kArtCompact) / 2;
                  final artSz     = lerpDouble(artFullSz, _kArtCompact, t)!;
                  final artL      = lerpDouble(artFullL,  _kArtCompactLeft, t)!;
                  final artT      = lerpDouble(artFullT,  artCompactT, t)!;
                  final artRadius = lerpDouble(16.0, 8.0, t)!;

                  final bloomOpacity   = (1.0 - t * 3.0).clamp(0.0, 1.0);
                  final fullOpacity    = (1.0 - t * 2.0).clamp(0.0, 1.0);
                  final compactOpacity = ((t - 0.3) / 0.7).clamp(0.0, 1.0);

                  final shadowAlpha = lerpDouble(0x66, 0x22, t)!.round().clamp(0, 255);

                  return Stack(
                    fit: StackFit.expand,
                    children: [

                      // ── [A] Full player (top bar lives here, hidden in queue mode) ──
                      Positioned.fill(
                        child: Opacity(
                          opacity: fullOpacity,
                          child: IgnorePointer(
                            ignoring: t > 0.3,
                            child: Column(
                              children: [
                                _buildTopBar(context),
                                Expanded(
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      if (bloomOpacity > 0.01) ...[
                                        Opacity(
                                          opacity: bloomOpacity,
                                          child: Container(
                                            width:  artFullSz * 1.85,
                                            height: artFullSz * 1.85,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  widget.ambient.playButtonColor.withAlpha(0x44),
                                                  widget.ambient.playButtonColor.withAlpha(0),
                                                ],
                                                stops: const [0.3, 1.0],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Opacity(
                                          opacity: bloomOpacity,
                                          child: Container(
                                            width:  artFullSz * 1.18,
                                            height: artFullSz * 1.18,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  widget.ambient.playButtonColor.withAlpha(0x77),
                                                  widget.ambient.playButtonColor.withAlpha(0),
                                                ],
                                                stops: const [0.35, 1.0],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                _buildControlsPanel(context, isFired, palette),
                                _buildQueueHint(context),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── [B] Compact header + queue ────────────────────────
                      Positioned.fill(
                        child: Opacity(
                          opacity: compactOpacity,
                          child: IgnorePointer(
                            ignoring: t < 0.5,
                            child: Container(
                              color: const Color(0xFF0A0A14),
                              child: Column(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: widget.onCompactHeaderDragUpdate,
                                    onVerticalDragEnd:    widget.onCompactHeaderDragEnd,
                                    child: SizedBox(
                                      height: _kCompactHeaderH,
                                      child: Row(
                                        children: [
                                          // Spacer for [C] art widget
                                          const SizedBox(
                                              width: _kArtCompactLeft + _kArtCompact + 12),
                                          // Title + artist
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  widget.item.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  widget.item.artist ?? '',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white.withAlpha(0x99),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Prev
                                          _PlainIconButton(
                                            icon: Icons.skip_previous_rounded,
                                            iconSize: 26,
                                            inactiveColor: Colors.white.withAlpha(0xDD),
                                            activeColor: widget.ambient.waveformActive,
                                            onTap: widget.handler.skipToPrevious,
                                          ),
                                          // Play / Pause
                                          StreamBuilder<PlaybackState>(
                                            stream: widget.handler.playbackState,
                                            builder: (ctx, snap) {
                                              final playing = snap.data?.playing ?? false;
                                              return _PlainIconButton(
                                                icon: playing
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                                iconSize: 28,
                                                inactiveColor: Colors.white.withAlpha(0xDD),
                                                activeColor: Colors.white,
                                                onTap: () => playing
                                                    ? widget.handler.pause()
                                                    : widget.handler.play(),
                                              );
                                            },
                                          ),
                                          // Next
                                          _PlainIconButton(
                                            icon: Icons.skip_next_rounded,
                                            iconSize: 26,
                                            inactiveColor: Colors.white.withAlpha(0xDD),
                                            activeColor: widget.ambient.waveformActive,
                                            onTap: widget.handler.skipToNext,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Divider(color: Colors.white12, height: 1),
                                  // ViBE Queue header
                                  StreamBuilder<List<MediaItem>>(
                                    stream: widget.handler.queue,
                                    builder: (ctx, snap) {
                                      final count =
                                          (snap.data ?? widget.handler.queue.value).length;
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                                        child: Row(
                                          children: [
                                            const Text(
                                              'ViBE Queue',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$count songs',
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(0x66),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  Expanded(
                                    child: RepaintBoundary(child: _buildQueueList()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ── [C] Real art — lerped position/size ───────────────
                      Positioned(
                        left:   artL,
                        top:    artT,
                        width:  artSz,
                        height: artSz,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(artRadius),
                            boxShadow: [
                              BoxShadow(
                                color: widget.ambient.playButtonColor
                                    .withAlpha(shadowAlpha),
                                blurRadius:   lerpDouble(60, 10, t)!,
                                spreadRadius: lerpDouble(6,  0,  t)!,
                                offset: Offset(0, lerpDouble(20, 4, t)!),
                              ),
                              BoxShadow(
                                color:      Colors.black54,
                                blurRadius: lerpDouble(24, 8, t)!,
                                offset:     Offset(0, lerpDouble(8, 2, t)!),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(artRadius),
                            child: _SeekableAlbumArt(
                              artUrl:  widget.artUrl,
                              size:    artSz,
                              ambient: widget.ambient,
                              handler: widget.handler,
                              theme:   widget.theme,
                            ),
                          ),
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

// ── Single queue row ────────────────────────────────────────────────────────
class _QueueItem extends StatelessWidget {
  final int          index;
  final MediaItem    track;
  final bool         isCurrent;
  final VibeTheme    theme;
  final VoidCallback onTap;

  const _QueueItem({
    super.key,
    required this.index,
    required this.track,
    required this.isCurrent,
    required this.theme,
    required this.onTap,
  });

  static String _fmtDuration(Duration? d) {
    if (d == null || d.inSeconds == 0) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? Colors.white.withAlpha(0x0F) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    if (track.artUri != null)
                      CachedNetworkImage(
                        imageUrl: track.artUri.toString(),
                        width: 44, height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(width: 44, height: 44, color: theme.surface),
                      )
                    else
                      Container(width: 44, height: 44, color: theme.surface),
                    if (isCurrent)
                      Container(
                        width: 44, height: 44,
                        color: Colors.black.withAlpha(0x88),
                        child: Center(
                          child: _AnimatedEqualizer(color: theme.accentBright),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? theme.accentBright : Colors.white,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (track.artist?.isNotEmpty == true) track.artist!,
                        _fmtDuration(track.duration),
                      ].where((s) => s.isNotEmpty).join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(0x77),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Icon(Icons.drag_handle_rounded,
                      color: Colors.white.withAlpha(0x33), size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
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
    _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
    final Color dark = Color.lerp(palette.core, Colors.black, 0.42)!;

    final int gA1 = (0x55 * intensity).round().clamp(0, 255);
    final int gA2 = (0x33 * intensity).round().clamp(0, 255);
    final int gA3 = (0x1A * intensity).round().clamp(0, 255);

    final double gradSize = size * 0.62;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size, height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
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
            customIcon ?? Icon(icon, color: Colors.white, size: iconSize),
          ],
        ),
      ),
    );
  }
}

// ── Thin pause bars ─────────────────────────────────────────────────────────
class _ThinPauseIcon extends StatelessWidget {
  final double height;
  const _ThinPauseIcon({this.height = 20});

  @override
  Widget build(BuildContext context) {
    final barW   = (height * 0.16).clamp(2.5, 4.0);
    final gap    = height * 0.30;
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

// ── Seekable album art — double-tap ±10s + swipe left/right to skip ─────────
class _SeekableAlbumArt extends StatefulWidget {
  final String?          artUrl;
  final double           size;
  final AmbientTheme     ambient;
  final VibeAudioHandler handler;
  final VibeTheme        theme;

  const _SeekableAlbumArt({
    required this.artUrl,
    required this.size,
    required this.ambient,
    required this.handler,
    required this.theme,
  });

  @override
  State<_SeekableAlbumArt> createState() => _SeekableAlbumArtState();
}

class _SeekableAlbumArtState extends State<_SeekableAlbumArt>
    with TickerProviderStateMixin {
  late final AnimationController _bleedCtrl;
  late final AnimationController _labelCtrl;
  late final Animation<double>   _bleedOpacity;
  late final Animation<double>   _labelOpacity;
  late final Animation<double>   _labelScale;

  bool _isRight = false;
  Duration _pos = Duration.zero;
  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.handler.positionStream.listen((p) => _pos = p);

    _bleedCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _labelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));

    _bleedOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0),   weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.88),  weight: 56),
      TweenSequenceItem(tween: Tween(begin: 0.88, end: 0.0),  weight: 26),
    ]).animate(CurvedAnimation(parent: _bleedCtrl, curve: Curves.easeInOut));

    _labelOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 17),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 28),
    ]).animate(_labelCtrl);

    _labelScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0,  end: 0.0),  weight: 5),
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.08), weight: 17),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0),  weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0,  end: 0.94), weight: 28),
    ]).animate(CurvedAnimation(parent: _labelCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bleedCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _onDoubleTap(TapDownDetails d) {
    final isRight = d.localPosition.dx > widget.size / 2;
    setState(() => _isRight = isRight);

    final delta  = Duration(seconds: isRight ? 10 : -10);
    final maxDur = widget.handler.duration ?? const Duration(hours: 1);
    var target   = _pos + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > maxDur) target = maxDur;
    widget.handler.seek(target);

    _bleedCtrl.forward(from: 0);
    _labelCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.ambient.waveformActive;

    return GestureDetector(
      onDoubleTapDown: _onDoubleTap,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -400) {
          widget.handler.skipToNext();
        } else if (v > 400) {
          widget.handler.skipToPrevious();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.artUrl != null
                ? CachedNetworkImage(
                    imageUrl: widget.artUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: widget.theme.surface),
                    errorWidget: (_, _, _) => Container(color: widget.theme.surface),
                  )
                : Container(color: widget.theme.surface),

            AnimatedBuilder(
              animation: _bleedCtrl,
              builder: (_, child) => Opacity(
                opacity: _bleedOpacity.value,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: _isRight ? Alignment.centerLeft : Alignment.centerRight,
                      end:   _isRight ? Alignment.centerRight : Alignment.centerLeft,
                      colors: [
                        Colors.transparent,
                        accentColor.withAlpha(0x66),
                        accentColor.withAlpha(0xCC),
                      ],
                      stops: const [0.42, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            AnimatedBuilder(
              animation: _labelCtrl,
              builder: (_, child) => Opacity(
                opacity: _labelOpacity.value,
                child: Align(
                  alignment: Alignment(_isRight ? 0.72 : -0.72, 0),
                  child: Transform.scale(
                    scale: _labelScale.value,
                    child: Text(
                      _isRight ? '›› +10s' : '‹‹ −10s',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        shadows: [
                          Shadow(color: accentColor, blurRadius: 24),
                          const Shadow(
                              color: Colors.black54,
                              blurRadius: 10,
                              offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Waveform seek bar ───────────────────────────────────────────────────────
class _WaveformSeekBar extends StatefulWidget {
  final double progress;
  final String trackId;
  final Color  colorAnchor;
  final Color  colorMid;
  final Color  colorEnd;
  final Color  colorTail;
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

  @override
  State<_WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<_WaveformSeekBar> {
  double? _drag;

  double _ratio(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(globalPos);
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => widget.onSeek(_ratio(d.globalPosition)),
      onHorizontalDragUpdate: (d) =>
          setState(() => _drag = _ratio(d.globalPosition)),
      onHorizontalDragEnd: (_) {
        if (_drag != null) {
          widget.onSeek(_drag!);
          setState(() => _drag = null);
        }
      },
      onHorizontalDragCancel: () => setState(() => _drag = null),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            progress:      _drag ?? widget.progress,
            colorAnchor:   widget.colorAnchor,
            colorMid:      widget.colorMid,
            colorEnd:      widget.colorEnd,
            colorTail:     widget.colorTail,
            inactiveColor: widget.inactiveColor,
          ),
          key: ValueKey(widget.trackId),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color  colorAnchor;
  final Color  colorMid;
  final Color  colorEnd;
  final Color  colorTail;
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
    const barCount = 55;
    const gap      = 2.5;
    final barW     = (size.width - (barCount - 1) * gap) / barCount;
    final maxH     = size.height;
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
      progress    != old.progress    ||
      colorAnchor != old.colorAnchor ||
      colorMid    != old.colorMid    ||
      colorEnd    != old.colorEnd    ||
      colorTail   != old.colorTail;
}
