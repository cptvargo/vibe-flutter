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
  final Color waveformAnchor; // darkVibrant — deep start of gradient
  final Color waveformTail;   // muted — soft resolution at end of gradient

  const AmbientTheme({
    required this.glowColor,
    required this.artworkGlow,
    required this.backgroundDark,
    required this.playButtonColor,
    required this.playButtonGlow,
    required this.rimColor,
    required this.waveformActive,
    required this.waveformInactive,
    required this.waveformAnchor,
    required this.waveformTail,
  });

  factory AmbientTheme.from(VibePalette p) {
    final maxSat    = [p.vibrant, p.darkVibrant, p.muted]
        .map((c) => HSLColor.fromColor(c).saturation)
        .reduce((a, b) => a > b ? a : b);
    final lightHSL  = HSLColor.fromColor(p.lightVibrant);
    final vibrantHSL = HSLColor.fromColor(p.vibrant);

    // ── Achromatic (black / grey) ─────────────────────────────────────────
    // All swatches have near-zero saturation. Boost the hue slightly so the
    // waveform has a gentle silver-cool or silver-warm tint rather than flat grey.
    if (maxSat < 0.12) {
      final hslAnchor = HSLColor.fromColor(p.darkVibrant);
      final hslTail   = HSLColor.fromColor(p.muted);

      final light  = lightHSL
          .withSaturation(lightHSL.saturation.clamp(0.15, 0.30))
          .withLightness(lightHSL.lightness.clamp(0.60, 0.82))
          .toColor();
      final anchor = hslAnchor
          .withSaturation(hslAnchor.saturation.clamp(0.12, 0.25))
          .withLightness(hslAnchor.lightness.clamp(0.22, 0.42))
          .toColor();
      final tail   = hslTail
          .withSaturation(hslTail.saturation.clamp(0.10, 0.22))
          .withLightness(hslTail.lightness.clamp(0.38, 0.58))
          .toColor();
      final bgDark = Color.lerp(p.darkVibrant, Colors.black, 0.85) ?? Colors.black;

      return AmbientTheme(
        glowColor:        light,
        artworkGlow:      light,
        backgroundDark:   bgDark,
        playButtonColor:  anchor,
        playButtonGlow:   light.withAlpha(0xCC),
        rimColor:         light.withAlpha(0x77),
        waveformActive:   light,
        waveformInactive: Colors.white.withAlpha(0x28),
        waveformAnchor:   anchor,
        waveformTail:     tail,
      );
    }

    // ── White / bright album ──────────────────────────────────────────────
    // lightVibrant is very bright AND desaturated — the image is dominated by
    // white space (e.g. white background, white clothing). A small saturated
    // element like hair or a logo can drive maxSat high, but it shouldn't
    // colour the whole player. Carry the hue at very low saturation instead.
    if (lightHSL.lightness > 0.80 && lightHSL.saturation < 0.25) {
      final sat    = vibrantHSL.saturation.clamp(0.0, 0.16).toDouble();
      final light  = HSLColor.fromAHSL(1.0, vibrantHSL.hue, sat,        0.74).toColor();
      final anchor = HSLColor.fromAHSL(1.0, vibrantHSL.hue, sat,        0.40).toColor();
      final tail   = HSLColor.fromAHSL(1.0, vibrantHSL.hue, sat * 0.75, 0.56).toColor();
      final bgDark = Color.lerp(
        HSLColor.fromAHSL(1.0, vibrantHSL.hue, 0.15, 0.08).toColor(),
        Colors.black, 0.82,
      ) ?? Colors.black;

      return AmbientTheme(
        glowColor:        light,
        artworkGlow:      light,
        backgroundDark:   bgDark,
        playButtonColor:  anchor,
        playButtonGlow:   light.withAlpha(0xCC),
        rimColor:         light.withAlpha(0x77),
        waveformActive:   light,
        waveformInactive: Colors.white.withAlpha(0x28),
        waveformAnchor:   anchor,
        waveformTail:     tail,
      );
    }

    // ── Colored albums ────────────────────────────────────────────────────
    final base    = _pickBase([p.vibrant, p.darkVibrant, p.muted]);
    final vibrant = _clampHSL(base,           minL: 0.36, maxL: 0.60, minS: 0.50);
    final light   = _clampHSL(p.lightVibrant, minL: 0.55, maxL: 0.82, minS: 0.48);
    final anchor  = _clampHSL(p.darkVibrant,  minL: 0.28, maxL: 0.48, minS: 0.40);
    final tail    = _clampHSL(p.muted,        minL: 0.38, maxL: 0.58, minS: 0.18);
    final bgDark  = Color.lerp(p.darkVibrant, Colors.black, 0.90) ?? Colors.black;

    return AmbientTheme(
      glowColor:        vibrant,
      artworkGlow:      vibrant,
      backgroundDark:   bgDark,
      playButtonColor:  vibrant,
      playButtonGlow:   vibrant.withAlpha(0xCC),
      rimColor:         light.withAlpha(0x77),
      waveformActive:   light,
      waveformInactive: Colors.white.withAlpha(0x28),
      waveformAnchor:   anchor,
      waveformTail:     tail,
    );
  }

  static const fallback = AmbientTheme(
    glowColor:        Color(0xFF7C3AED),
    artworkGlow:      Color(0xFF7C3AED),
    backgroundDark:   Color(0xFF04040F),
    playButtonColor:  Color(0xFF7C3AED),
    playButtonGlow:   Color(0xCC7C3AED),
    rimColor:         Color(0x779F67F0),
    waveformActive:   Color(0xFF9F67F0),
    waveformInactive: Color(0x28FFFFFF),
    waveformAnchor:   Color(0xFF5B21B6),
    waveformTail:     Color(0xFF7C6B9E),
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
    waveformAnchor:   Color.lerp(a.waveformAnchor,   b.waveformAnchor,   t)!,
    waveformTail:     Color.lerp(a.waveformTail,     b.waveformTail,     t)!,
  );

  // Returns the most saturated color from candidates — used to avoid forcing a hue
  // onto an achromatic color (white/gray album art) which would produce arbitrary pink/red.
  static Color _pickBase(List<Color> candidates) => candidates.reduce((a, b) =>
    HSLColor.fromColor(a).saturation >= HSLColor.fromColor(b).saturation ? a : b);

  static Color _clampHSL(Color c, {double minL = 0.0, double maxL = 1.0, double minS = 0.0}) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(hsl.lightness.clamp(minL, maxL))
        .withSaturation(hsl.saturation.clamp(minS, 1.0))
        .toColor();
  }
}
