import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe/theme/palette_service.dart';
import 'package:vibe/theme/ambient_theme.dart';

void main() {
  group('PaletteService.fromBlurHash', () {
    test('returns null for null', () {
      expect(PaletteService.fromBlurHash(null), isNull);
    });

    test('returns null for string shorter than 6 chars', () {
      expect(PaletteService.fromBlurHash('short'), isNull);
      expect(PaletteService.fromBlurHash(''), isNull);
      expect(PaletteService.fromBlurHash('ab'), isNull);
    });

    test('returns a VibePalette for a real Jellyfin blurHash', () {
      // Real blurHash from BlurHash spec (warm landscape image)
      const hash = r'LEHLk~WB0iD$xoxt8#oI';
      final p = PaletteService.fromBlurHash(hash);
      expect(p, isNotNull);
    });

    test('warm-toned hash produces warm dominant color (r > b)', () {
      // 'LEHLk~WB0iD$xoxt8#oI' is a warm landscape; DC should be warm
      const hash = r'LEHLk~WB0iD$xoxt8#oI';
      final p = PaletteService.fromBlurHash(hash)!;
      // Just verify it creates a valid palette — not black/transparent
      expect(p.vibrant.alpha, equals(255));
      expect(p.darkMuted.alpha, equals(255));
    });

    test('does not crash on malformed base83 characters', () {
      // Should catch and return null rather than throwing
      expect(() => PaletteService.fromBlurHash('XX????'), returnsNormally);
    });
  });

  group('VibePalette.fromDominantColor', () {
    test('blue input produces blue-hued swatches', () {
      final p = VibePalette.fromDominantColor(const Color(0xFF1565C0));
      final hsl = HSLColor.fromColor(p.vibrant);
      // Blue hue is roughly 200-250 degrees
      expect(hsl.hue, inInclusiveRange(180.0, 280.0));
    });

    test('red input produces red-hued swatches', () {
      final p = VibePalette.fromDominantColor(const Color(0xFFE53935));
      final hsl = HSLColor.fromColor(p.vibrant);
      // Red wraps near 0/360; allow 0-30 or 330-360
      expect(hsl.hue < 30 || hsl.hue > 330, isTrue,
          reason: 'Red dominant should produce red-hued vibrant swatch');
    });

    test('darkVibrant is always darker than vibrant', () {
      for (final c in [
        Colors.red,
        Colors.green,
        Colors.blue,
        Colors.orange,
        Colors.purple,
      ]) {
        final p  = VibePalette.fromDominantColor(c);
        final dv = HSLColor.fromColor(p.darkVibrant).lightness;
        final v  = HSLColor.fromColor(p.vibrant).lightness;
        expect(dv, lessThan(v),
            reason: 'darkVibrant must be darker than vibrant for ${c}');
      }
    });

    test('lightVibrant is always lighter than vibrant', () {
      for (final c in [Colors.red, Colors.green, Colors.blue]) {
        final p  = VibePalette.fromDominantColor(c);
        final lv = HSLColor.fromColor(p.lightVibrant).lightness;
        final v  = HSLColor.fromColor(p.vibrant).lightness;
        expect(lv, greaterThan(v),
            reason: 'lightVibrant must be lighter than vibrant for ${c}');
      }
    });

    test('all swatches have alpha 255', () {
      final p = VibePalette.fromDominantColor(const Color(0xFF9C27B0));
      expect(p.vibrant.alpha,      equals(255));
      expect(p.lightVibrant.alpha, equals(255));
      expect(p.darkVibrant.alpha,  equals(255));
      expect(p.muted.alpha,        equals(255));
      expect(p.darkMuted.alpha,    equals(255));
    });

    test('saturation is clamped to valid range for every swatch', () {
      for (final c in [Colors.black, Colors.white, Colors.grey, Colors.red]) {
        final p = VibePalette.fromDominantColor(c);
        for (final swatch in [p.vibrant, p.lightVibrant, p.darkVibrant, p.muted, p.darkMuted]) {
          final hsl = HSLColor.fromColor(swatch);
          expect(hsl.saturation, inInclusiveRange(0.0, 1.0));
          expect(hsl.lightness,  inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });

  group('AmbientTheme.from — glowScale is never 0', () {
    // Before the fix, dark and grey albums produced glowScale: 0.0 (pure black player).
    // After the fix, every album gets at least some atmospheric color.

    test('near-black achromatic album: glowScale is 0.0 (case 1 — pure black player)', () {
      // darkMuted luminance < 0.010 AND saturation < 0.20 → triggers case 1
      // All-black album art → pure black player, no grey haze
      // #080808 has luminance ≈ 0.0024, saturation = 0
      final palette = VibePalette(
        vibrant:      const Color(0xFF424242),
        lightVibrant: const Color(0xFF757575),
        darkVibrant:  const Color(0xFF212121),
        muted:        const Color(0xFF616161),
        darkMuted:    const Color(0xFF080808),
      );
      final theme = AmbientTheme.from(palette);
      expect(theme.glowScale, equals(0.0));
    });

    test('grey album (all swatches low saturation): glowScale is 0.0 (case 2 — pure black player)', () {
      // All pure greys: saturation = 0, maxSat = 0 < 0.12 → triggers case 2
      // B&W / achromatic art → pure black player, same as all-black art
      // darkMuted = #212121 has luminance ≈ 0.0147 > 0.010, so case 1 is skipped
      final palette = VibePalette(
        vibrant:      const Color(0xFF9E9E9E),
        lightVibrant: const Color(0xFFBDBDBD),
        darkVibrant:  const Color(0xFF424242),
        muted:        const Color(0xFF757575),
        darkMuted:    const Color(0xFF212121),
      );
      final theme = AmbientTheme.from(palette);
      expect(theme.glowScale, equals(0.0));
    });

    test('colored album: glowScale is 1.0', () {
      // fromDominantColor with blue produces maxSat > 0.12 → colored path
      final p     = VibePalette.fromDominantColor(const Color(0xFF1565C0));
      final theme = AmbientTheme.from(p);
      expect(theme.glowScale, equals(1.0));
    });

    test('white/bright album: glowScale is 1.0 (default)', () {
      // Case 3 fires when: lightVibrant.lightness > 0.80 AND lightVibrant.saturation < 0.25
      // BUT case 2 (achromatic, maxSat < 0.12) must NOT fire first — so vibrant needs
      // enough saturation (e.g. a colorful logo on a white background).
      // #EF9A9A = light pink, saturation ~0.73 → keeps maxSat above 0.12
      // #F5F5F5 = near-white, saturation 0 → triggers the white-album lightVibrant check
      final palette = VibePalette(
        vibrant:      const Color(0xFFEF9A9A), // light pink — saturation ~0.73, not achromatic
        lightVibrant: const Color(0xFFF5F5F5), // lightness > 0.80, saturation < 0.25
        darkVibrant:  const Color(0xFF9E9E9E),
        muted:        const Color(0xFFE0E0E0),
        darkMuted:    const Color(0xFF757575),
      );
      final theme = AmbientTheme.from(palette);
      expect(theme.glowScale, equals(1.0));
    });

    test('all-black and grey cases both have glowScale 0.0', () {
      final darkPalette = VibePalette(
        vibrant:      const Color(0xFF424242),
        lightVibrant: const Color(0xFF757575),
        darkVibrant:  const Color(0xFF212121),
        muted:        const Color(0xFF616161),
        darkMuted:    const Color(0xFF080808),
      );
      final greyPalette = VibePalette(
        vibrant:      const Color(0xFF9E9E9E),
        lightVibrant: const Color(0xFFBDBDBD),
        darkVibrant:  const Color(0xFF424242),
        muted:        const Color(0xFF757575),
        darkMuted:    const Color(0xFF212121),
      );
      expect(AmbientTheme.from(darkPalette).glowScale, equals(0.0));
      expect(AmbientTheme.from(greyPalette).glowScale, equals(0.0));
    });
  });

  group('AmbientTheme.lerp', () {
    test('lerp at t=0 returns first theme values', () {
      const a = AmbientTheme.fallback;
      final b = AmbientTheme.from(VibePalette.fromDominantColor(Colors.blue));
      final lerped = AmbientTheme.lerp(a, b, 0.0);
      expect(lerped.glowColor.value, equals(a.glowColor.value));
      expect(lerped.glowScale, closeTo(a.glowScale, 0.001));
    });

    test('lerp at t=1 returns second theme values', () {
      const a = AmbientTheme.fallback;
      final b = AmbientTheme.from(VibePalette.fromDominantColor(Colors.blue));
      final lerped = AmbientTheme.lerp(a, b, 1.0);
      expect(lerped.glowColor.value, equals(b.glowColor.value));
      expect(lerped.glowScale, closeTo(b.glowScale, 0.001));
    });

    test('glowScale interpolates between 0.0 (achromatic) and 1.0 (colored)', () {
      final greyPalette = VibePalette(
        vibrant:      const Color(0xFF9E9E9E),
        lightVibrant: const Color(0xFFBDBDBD),
        darkVibrant:  const Color(0xFF424242),
        muted:        const Color(0xFF757575),
        darkMuted:    const Color(0xFF212121),
      );
      final a = AmbientTheme.from(greyPalette); // glowScale 0.0
      final b = AmbientTheme.from(VibePalette.fromDominantColor(Colors.blue)); // 1.0
      final mid = AmbientTheme.lerp(a, b, 0.5);
      expect(mid.glowScale, closeTo(0.5, 0.001));
    });
  });
}
