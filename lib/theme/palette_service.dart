import 'dart:math' show pow;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:http/http.dart' as http;

// Persistent color cache — keyed by itemId, survives app restarts
// Same concept as our AsyncStorage cache in React Native but faster (Hive is binary)
class PaletteService {
  static const _boxName = 'vibe_palettes_v2';
  static Box<Map>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>(_boxName);
  }

  // Extract palette from a 32px color URL, returns dominant + accent colors
  static Future<VibePalette?> extractFromUrl(String colorUrl, String cacheKey) async {
    // Tier 0: persistent cache — instant
    final cached = _box?.get(cacheKey);
    if (cached != null) return VibePalette.fromMap(cached);

    try {
      // Download the 32px thumbnail
      final response = await http.get(Uri.parse(colorUrl));
      if (response.statusCode != 200) return null;

      // Decode image bytes
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // Run palette extraction on an isolate — never blocks UI thread
      final generator = await PaletteGenerator.fromImage(image);

      final palette = VibePalette.fromGenerator(generator);
      _box?.put(cacheKey, palette.toMap());
      return palette;
    } catch (_) {
      return null;
    }
  }

  // Pre-warm: silently extract and cache without affecting current UI
  static Future<void> prewarm(String colorUrl, String cacheKey) async {
    if (_box?.containsKey(cacheKey) == true) return;
    await extractFromUrl(colorUrl, cacheKey);
  }

  // Decode the DC (average) component of a BlurHash string into a dominant color,
  // then synthesize a full VibePalette from it. Returns null if the hash is missing
  // or malformed. Used to show the right hue instantly before extractFromUrl completes.
  static VibePalette? fromBlurHash(String? blurHash) {
    if (blurHash == null || blurHash.length < 6) return null;
    try {
      const chars =
          '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
          r'#$%*+,-./:;=?@[]^_{|}~';
      int decode83(String s) {
        var val = 0;
        for (final rune in s.runes) {
          final idx = chars.indexOf(String.fromCharCode(rune));
          if (idx < 0) return 0;
          val = val * 83 + idx;
        }
        return val;
      }
      // BlurHash DC channels are in linear light; convert to sRGB before use.
      double toSrgb(int linearByte) {
        final c = linearByte / 255.0;
        return c <= 0.0031308 ? c * 12.92 : 1.055 * (pow(c, 1.0 / 2.4) as double) - 0.055;
      }
      final dc = decode83(blurHash.substring(2, 6));
      final r  = (toSrgb((dc >> 16) & 0xff) * 255).round().clamp(0, 255);
      final g  = (toSrgb((dc >> 8)  & 0xff) * 255).round().clamp(0, 255);
      final b  = (toSrgb(dc         & 0xff) * 255).round().clamp(0, 255);
      return VibePalette.fromDominantColor(Color.fromARGB(255, r, g, b));
    } catch (_) {
      return null;
    }
  }
}

class VibePalette {
  final Color vibrant;
  final Color lightVibrant;
  final Color darkVibrant;
  final Color muted;
  final Color darkMuted;

  const VibePalette({
    required this.vibrant,
    required this.lightVibrant,
    required this.darkVibrant,
    required this.muted,
    required this.darkMuted,
  });

  static const fallback = VibePalette(
    vibrant:      Color(0xFF7C3AED),
    lightVibrant: Color(0xFF9F67F0),
    darkVibrant:  Color(0xFF4C1D95),
    muted:        Color(0xFF6B5B95),
    darkMuted:    Color(0xFF1E1333),
  );

  // Synthesize a full 5-swatch palette from a single dominant color.
  // Used by fromBlurHash() to produce an instant-bootstrap palette before
  // the real palette is extracted.
  factory VibePalette.fromDominantColor(Color dominant) {
    final hsl = HSLColor.fromColor(dominant);
    return VibePalette(
      vibrant:      hsl
          .withSaturation(hsl.saturation.clamp(0.30, 1.0))
          .withLightness(hsl.lightness.clamp(0.35, 0.65))
          .toColor(),
      lightVibrant: hsl
          .withSaturation(hsl.saturation.clamp(0.20, 0.90))
          .withLightness((hsl.lightness + 0.20).clamp(0.50, 0.85))
          .toColor(),
      darkVibrant:  hsl
          .withSaturation(hsl.saturation.clamp(0.30, 1.0))
          .withLightness((hsl.lightness - 0.20).clamp(0.08, 0.35))
          .toColor(),
      muted:        hsl
          .withSaturation((hsl.saturation * 0.60).clamp(0.05, 0.50))
          .withLightness(hsl.lightness.clamp(0.30, 0.60))
          .toColor(),
      darkMuted:    hsl
          .withSaturation((hsl.saturation * 0.50).clamp(0.04, 0.40))
          .withLightness((hsl.lightness - 0.25).clamp(0.04, 0.30))
          .toColor(),
    );
  }

  factory VibePalette.fromGenerator(PaletteGenerator g) {
    // Use the dominant color as fallback — gives each album its own natural
    // theme even for monochromatic art (grey album → grey theme, not purple)
    final dominant = g.dominantColor?.color ?? VibePalette.fallback.vibrant;

    // Clamp darkVibrant lightness ≤ 0.35 so achromatic/B&W art never
    // propagates a near-white value into dark slots, which would make
    // surface and background near-identical and flip textColor to black.
    Color clampDark(Color c) {
      final hsl = HSLColor.fromColor(c);
      return hsl.lightness > 0.35
          ? hsl.withLightness(0.35).toColor()
          : c;
    }

    final rawDarkVibrant = g.darkVibrantColor?.color ?? g.darkMutedColor?.color ?? dominant;

    return VibePalette(
      vibrant:      g.vibrantColor?.color      ?? g.mutedColor?.color     ?? dominant,
      lightVibrant: g.lightVibrantColor?.color ?? g.vibrantColor?.color   ?? dominant,
      darkVibrant:  clampDark(rawDarkVibrant),
      muted:        g.mutedColor?.color        ?? g.darkMutedColor?.color ?? dominant,
      darkMuted:    g.darkMutedColor?.color    ?? g.mutedColor?.color     ?? dominant,
    );
  }

  factory VibePalette.fromMap(Map m) => VibePalette(
    vibrant:      Color(m['vibrant'] as int),
    lightVibrant: Color(m['lightVibrant'] as int),
    darkVibrant:  Color(m['darkVibrant'] as int),
    muted:        Color(m['muted'] as int),
    darkMuted:    Color(m['darkMuted'] as int),
  );

  Map<String, int> toMap() => {
    'vibrant':      vibrant.toARGB32(),
    'lightVibrant': lightVibrant.toARGB32(),
    'darkVibrant':  darkVibrant.toARGB32(),
    'muted':        muted.toARGB32(),
    'darkMuted':    darkMuted.toARGB32(),
  };
}
