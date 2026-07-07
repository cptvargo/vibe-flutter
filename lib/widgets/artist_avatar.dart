import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/jellyfin_api.dart';
import '../theme/vibe_theme.dart';

// Local asset overrides — keyed by lowercase artist name, value is asset path.
// Add an entry here whenever you have a custom artist image in assets/artists/.
const _kArtistAssets = <String, String>{
  'nameless generation': 'assets/artists/NG.png',
};

class ArtistAvatar extends StatelessWidget {
  /// Returns the bundled asset path for [name], or null if none registered.
  static String? localAssetPath(String name) =>
      _kArtistAssets[name.trim().toLowerCase()];
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
    final initials  = _initials(name);
    final radius    = circle ? size / 2 : size * 0.18;
    final assetPath = _kArtistAssets[name.trim().toLowerCase()];

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

    final clip = BorderRadius.circular(radius);

    // Use bundled asset if available, otherwise fetch from Jellyfin
    if (assetPath != null) {
      return ClipRRect(
        borderRadius: clip,
        child: Image.asset(
          assetPath,
          width: size, height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    }

    return ClipRRect(
      borderRadius: clip,
      child: CachedNetworkImage(
        imageUrl: JellyfinApi.imageUrl(id, size: size.toInt()),
        width: size, height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            Container(width: size, height: size, color: theme.surface),
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
