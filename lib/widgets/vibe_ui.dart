import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/jellyfin_api.dart';
import '../theme/vibe_theme.dart';
import 'artist_avatar.dart';

typedef VibeStation = ({String id, String label, IconData icon, String sub});

// ── Bounce tap wrapper ────────────────────────────────────────────────────────

class VibeBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const VibeBounce({super.key, required this.child, this.onTap});
  @override State<VibeBounce> createState() => _VibeBounceState();
}

class _VibeBounceState extends State<VibeBounce> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) => setState(() => _scale = 0.93),
    onTapUp:     (_) { setState(() => _scale = 1.0); widget.onTap?.call(); },
    onTapCancel: ()  => setState(() => _scale = 1.0),
    child: AnimatedScale(
      scale:    _scale,
      duration: const Duration(milliseconds: 110),
      curve:    Curves.easeOut,
      child:    widget.child,
    ),
  );
}

// ── Fade + slide entrance ─────────────────────────────────────────────────────

class VibeFadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const VibeFadeSlide({super.key, required this.animation, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(animation),
      child: child,
    ),
  );
}

// ── Breathing glow gradient ───────────────────────────────────────────────────

class VibeBreathingGlow extends StatefulWidget {
  final Color color;
  final Color? colorBright;
  final double heightFraction;
  const VibeBreathingGlow({
    super.key,
    required this.color,
    this.colorBright,
    this.heightFraction = 0.52,
  });

  @override State<VibeBreathingGlow> createState() => _VibeBreathingGlowState();
}

class _VibeBreathingGlowState extends State<VibeBreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h      = MediaQuery.of(context).size.height * widget.heightFraction;
    final bright = widget.colorBright ?? widget.color;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final t = _anim.value;
        return SizedBox(
          height: h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin:  Alignment.topCenter,
                end:    Alignment.bottomCenter,
                colors: [
                  bright.withAlpha((0x5A + (t * 0x55).round())),
                  widget.color.withAlpha((0x20 + (t * 0x30).round())),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.42, 0.84],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Section header with neon text glow ────────────────────────────────────────

class VibeSectionHeader extends StatelessWidget {
  final String title;
  final VibeTheme theme;
  const VibeSectionHeader({super.key, required this.title, required this.theme});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(title,
      style: TextStyle(
        color:         theme.textColor,
        fontSize:      18,
        fontWeight:    FontWeight.w700,
        letterSpacing: 0.4,
        shadows: [
          Shadow(color: theme.accent.withAlpha(0xCC),      blurRadius: 10),
          Shadow(color: theme.accentBright.withAlpha(0x66), blurRadius: 24),
        ],
      ),
    ),
  );
}

// ── Glass card base ───────────────────────────────────────────────────────────

class VibeGlassCard extends StatelessWidget {
  final Widget child;
  final VibeTheme theme;
  final double radius;
  final EdgeInsets? padding;
  const VibeGlassCard({
    super.key,
    required this.child,
    required this.theme,
    this.radius  = 14,
    this.padding,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color:      theme.accent.withAlpha(0x55),
          blurRadius: 18,
          spreadRadius: -2,
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color:        theme.surface.withAlpha(0xBB),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: theme.accent.withAlpha(0x77), width: 0.8),
          ),
          child: child,
        ),
      ),
    ),
  );
}

// ── Station grid (2-col + wide last row if odd count) ─────────────────────────

class VibeStationGrid extends StatelessWidget {
  final List<VibeStation> stations;
  final VibeTheme theme;
  final void Function(String id) onTap;
  const VibeStationGrid({
    super.key,
    required this.stations,
    required this.theme,
    required this.onTap,
  });

  static const _fireIds = {'fire_mix', 'ai_fire'};

  Widget _card(VibeStation s) => VibeBounce(
    onTap: () => onTap(s.id),
    child: VibeGlassCard(
      theme:   theme,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.center,
        children: [
          Icon(s.icon, size: 28,
              color: _fireIds.contains(s.id)
                  ? const Color(0xFFFF6B1A)
                  : theme.accentBright),
          const SizedBox(height: 10),
          Text(s.label,
              style: TextStyle(color: theme.textColor, fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(s.sub,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textFaint, fontSize: 11)),
        ],
      ),
    ),
  );

  Widget _wideCard(VibeStation s) => VibeBounce(
    onTap: () => onTap(s.id),
    child: VibeGlassCard(
      theme:   theme,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(s.icon, size: 30,
              color: _fireIds.contains(s.id)
                  ? const Color(0xFFFF6B1A)
                  : theme.accentBright),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: TextStyle(color: theme.textColor, fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(s.sub,
                    style: TextStyle(color: theme.textFaint, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.textFaint, size: 20),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isOdd    = stations.length.isOdd;
    final gridList = isOdd ? stations.sublist(0, stations.length - 1) : stations;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            itemCount:  gridList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing:  12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemBuilder: (_, i) => _card(gridList[i]),
          ),
          if (isOdd) ...[
            const SizedBox(height: 12),
            SizedBox(height: 72, child: _wideCard(stations.last)),
          ],
        ],
      ),
    );
  }
}

// ── Album card with accent glow ───────────────────────────────────────────────

class VibeAlbumCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final double size;
  final VoidCallback? onPress;
  const VibeAlbumCard({
    super.key,
    required this.item,
    required this.theme,
    this.size    = 140,
    this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final itemId = item['Id'] as String? ?? '';
    final artUrl = itemId.isNotEmpty ? JellyfinApi.imageUrl(itemId, size: 300) : null;

    return VibeBounce(
      onTap: onPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color:        theme.accent.withAlpha(0x55),
                    blurRadius:   16,
                    spreadRadius: -2,
                    offset:       const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: artUrl != null
                    ? CachedNetworkImage(
                        imageUrl:    artUrl,
                        width:       size,
                        height:      size,
                        fit:         BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(width: size, height: size, color: theme.surface),
                        errorWidget: (_, _, _) =>
                            Container(width: size, height: size, color: theme.surface),
                      )
                    : Container(width: size, height: size, color: theme.surface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item['Name'] as String? ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textColor, fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              item['AlbumArtist'] as String?
                  ?? (item['Artists'] as List?)?.firstOrNull as String? ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Track row with glass pill ─────────────────────────────────────────────────

class VibeTrackRow extends StatelessWidget {
  final Map<String, dynamic> track;
  final VibeTheme theme;
  final VoidCallback? onPress;
  const VibeTrackRow({
    super.key,
    required this.track,
    required this.theme,
    this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final albumId = track['AlbumId']  as String?
        ?? track['ParentId'] as String?
        ?? track['Id']       as String? ?? '';
    final artUrl = albumId.isNotEmpty ? JellyfinApi.imageUrl(albumId, size: 100) : null;

    return VibeBounce(
      onTap: onPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color:        theme.tint1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.accent.withAlpha(0x28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: artUrl != null
                    ? CachedNetworkImage(
                        imageUrl:    artUrl,
                        width:       48,
                        height:      48,
                        fit:         BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(width: 48, height: 48, color: theme.surface),
                        errorWidget: (_, _, _) =>
                            Container(width: 48, height: 48, color: theme.surface),
                      )
                    : Container(width: 48, height: 48, color: theme.surface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track['Name'] as String? ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textColor, fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track['AlbumArtist'] as String?
                          ?? (track['Artists'] as List?)?.firstOrNull as String? ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_outline, color: theme.accentBright, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Artist card with neon glow ring ──────────────────────────────────────────

class VibeArtistCard extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VibeTheme theme;
  final double size;
  final VoidCallback? onPress;
  const VibeArtistCard({
    super.key,
    required this.artist,
    required this.theme,
    this.size    = 80,
    this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final id   = artist['Id']   as String? ?? '';
    final name = artist['Name'] as String? ?? '';

    return VibeBounce(
      onTap: onPress,
      child: SizedBox(
        width: size + 8,
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape:     BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:        theme.accentBright.withAlpha(0x66),
                    blurRadius:   18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ArtistAvatar(id: id, name: name, size: size, theme: theme),
            ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
