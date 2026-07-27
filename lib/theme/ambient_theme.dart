import 'package:flutter/material.dart';
import 'palette_service.dart';

class AmbientTheme {
  final Color glowColor;
  final Color artworkGlow;
  final Color backgroundDark;
  final Color playButtonColor;
  final Color playButtonGlow;
  final Color rimColor;
  final Color waveformActive;
  final Color waveformInactive;

  const AmbientTheme({
    required this.glowColor,
    required this.artworkGlow,
    required this.backgroundDark,
    required this.playButtonColor,
    required this.playButtonGlow,
    required this.rimColor,
    required this.waveformActive,
    required this.waveformInactive,
  });

  factory AmbientTheme.from(VibePalette p) {
    // Pure colors — no alpha baked in. Gradient layers control their own opacity
    // so we can apply non-linear, breathing-modulated alphas independently.
    final vibrant = _clampHSL(p.vibrant,      minL: 0.36, maxL: 0.60, minS: 0.55);
    final light   = _clampHSL(p.lightVibrant, minL: 0.55, maxL: 0.82, minS: 0.48);
    final bgDark  = Color.lerp(p.darkVibrant, Colors.black, 0.90) ?? Colors.black;

    return AmbientTheme(
      glowColor:        vibrant,                  // pure — alpha applied per-layer in widget
      artworkGlow:      vibrant,                  // pure — alpha applied per-layer in widget
      backgroundDark:   bgDark,
      playButtonColor:  vibrant,
      playButtonGlow:   vibrant.withAlpha(0xCC),
      rimColor:         light.withAlpha(0x77),
      waveformActive:   light,
      waveformInactive: Colors.white.withAlpha(0x28),
    );
  }

  static const fallback = AmbientTheme(
    glowColor:        Color(0xFF7C3AED),  // pure — alpha applied per-layer
    artworkGlow:      Color(0xFF7C3AED),  // pure — alpha applied per-layer
    backgroundDark:   Color(0xFF04040F),
    playButtonColor:  Color(0xFF7C3AED),
    playButtonGlow:   Color(0xCC7C3AED),
    rimColor:         Color(0x779F67F0),
    waveformActive:   Color(0xFF9F67F0),
    waveformInactive: Color(0x28FFFFFF),
  );

  static AmbientTheme lerp(AmbientTheme a, AmbientTheme b, double t) => AmbientTheme(
    glowColor:        Color.lerp(a.glowColor,        b.glowColor,        t)!,
    artworkGlow:      Color.lerp(a.artworkGlow,      b.artworkGlow,      t)!,
    backgroundDark:   Color.lerp(a.backgroundDark,   b.backgroundDark,   t)!,
    playButtonColor:  Color.lerp(a.playButtonColor,  b.playButtonColor,  t)!,
    playButtonGlow:   Color.lerp(a.playButtonGlow,   b.playButtonGlow,   t)!,
    rimColor:         Color.lerp(a.rimColor,          b.rimColor,         t)!,
    waveformActive:   Color.lerp(a.waveformActive,   b.waveformActive,   t)!,
    waveformInactive: Color.lerp(a.waveformInactive, b.waveformInactive, t)!,
  );

  static Color _clampHSL(Color c, {double minL = 0.0, double maxL = 1.0, double minS = 0.0}) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(hsl.lightness.clamp(minL, maxL))
        .withSaturation(hsl.saturation.clamp(minS, 1.0))
        .toColor();
  }
}
