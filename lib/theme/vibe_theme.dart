import 'package:flutter/material.dart';
import 'palette_service.dart';

// Built from a VibePalette — equivalent to buildTheme() in ThemeContext.js
class VibeTheme {
  final Color accent;
  final Color accentBright;
  final Color surface;
  final Color background;  // very dark, near-black — scaffold/page background
  final Color border;      // white at ~8% opacity
  final Color textColor;
  final Color textDim;
  final Color textFaint;
  final Color tint1;
  final Color tint2;
  final bool  textIsLight;

  const VibeTheme({
    required this.accent,
    required this.accentBright,
    required this.surface,
    required this.background,
    required this.border,
    required this.textColor,
    required this.textDim,
    required this.textFaint,
    required this.tint1,
    required this.tint2,
    required this.textIsLight,
  });

  static VibeTheme from(VibePalette p) {
    // Clamp lightness so accent colors are always visible on a dark background.
    // Too light → blends with white text. Too dark → invisible on dark surfaces.
    final accent       = _clampL(p.vibrant,      0.35, 0.65);
    final accentBright = _clampL(p.lightVibrant, 0.50, 0.80);
    final rawDark      = p.darkVibrant;
    final surface      = _darken(rawDark, 0.40);
    final background   = Color.lerp(rawDark, Colors.black, 0.88) ?? Colors.black;
    final isLight      = _pickTextIsLight(surface);
    final textColor    = isLight ? Colors.white : Colors.black;

    return VibeTheme(
      accent:       accent,
      accentBright: accentBright,
      surface:      surface,
      background:   background,
      border:       Colors.white.withAlpha(0x14),
      textColor:    textColor,
      textDim:      textColor.withAlpha(isLight ? 184 : 184),
      textFaint:    textColor.withAlpha(isLight ? 102 : 102),
      tint1:        _darken(rawDark, 0.10).withAlpha(0x66),
      tint2:        p.darkMuted.withAlpha(0x33),
      textIsLight:  isLight,
    );
  }

  static VibeTheme get defaults => VibeTheme.from(VibePalette.fallback);

  // ── Synthwave / AI theme ────────────────────────────────────────────────────

  // RN AI screen exact colors — matches what was in vibe-native
  static const _swBackground = Color(0xFF04040F);  // RN: #04040f page bg
  static const _swSurface    = Color(0xFF1A0030);  // RN: #1a0030 card surface
  static const _swViolet     = Color(0xFF7C3AED);  // RN: #7C3AED primary accent
  static const _swFuchsia    = Color(0xFFE879F9);  // RN: #E879F9 title glow
  static const _swTextDim    = Color(0xB8FFFFFF);  // rgba(255,255,255,0.72)
  static const _swTextFaint  = Color(0x66FFFFFF);  // rgba(255,255,255,0.40)

  // Synthwave theme: fixed RN dark base + album-art accent blended toward violet/fuchsia.
  // VibePalette.fallback already uses #7C3AED so the default renders as pure Synthwave.
  static VibeTheme synthwave(VibePalette p) {
    final albumAccent  = _clampL(p.vibrant,      0.40, 0.70);
    final albumBright  = _clampL(p.lightVibrant, 0.55, 0.85);
    final accent       = Color.lerp(albumAccent, _swViolet,  0.60)!;
    final accentBright = Color.lerp(albumBright, _swFuchsia, 0.70)!;

    return VibeTheme(
      accent:       accent,
      accentBright: accentBright,
      surface:      _swSurface,
      background:   _swBackground,
      border:       _swViolet.withAlpha(0x44),
      textColor:    Colors.white,
      textDim:      _swTextDim,
      textFaint:    _swTextFaint,
      tint1:        _swSurface.withAlpha(0x88),
      tint2:        const Color(0xFF0A0020).withAlpha(0x55),
      textIsLight:  true,
    );
  }

  // ── Color math ──────────────────────────────────────────────────────────────

  // Clamp HSL lightness so accent colors are always legible on dark backgrounds
  static Color _clampL(Color c, double min, double max) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(hsl.lightness.clamp(min, max)).toColor();
  }

  static Color _darken(Color c, double factor) {
    final f = (1 - factor.clamp(0.0, 1.0));
    return Color.fromARGB(
      (c.a * 255).round(),
      (c.r * 255 * f).round(),
      (c.g * 255 * f).round(),
      (c.b * 255 * f).round(),
    );
  }

  static double _relativeLuminance(Color c) {
    // c.r/g/b are already 0-1 in Flutter 3.x
    double linearize(double v) =>
        v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
    return 0.2126 * linearize(c.r)
         + 0.7152 * linearize(c.g)
         + 0.0722 * linearize(c.b);
  }

  static bool _pickTextIsLight(Color bg) {
    final lBg    = _relativeLuminance(bg);
    final lWhite = 1.0;
    final lBlack = 0.0;
    final cWhite = (lWhite + 0.05) / (lBg + 0.05);
    final cBlack = (lBg + 0.05)    / (lBlack + 0.05);
    return cWhite >= cBlack;
  }
}
