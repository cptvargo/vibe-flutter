import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/jellyfin_api.dart';
import '../theme/vibe_theme.dart';

class ArtistAvatar extends StatelessWidget {
  final String id;
  final String name;
  final double size;
  final VibeTheme theme;
  final bool circle;

  const ArtistAvatar({
    super.key,
    required this.id,
    required this.name,
    required this.size,
    required this.theme,
    this.circle = true,
  });

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final url      = JellyfinApi.imageUrl(id, size: size.toInt());
    final initials = _initials(name);
    final radius   = circle ? size / 2 : size * 0.18;

    final fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: theme.accent.withAlpha(0xCC),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: theme.textColor,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size, height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            Container(width: size, height: size, color: theme.surface),
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
