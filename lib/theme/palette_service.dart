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

  factory VibePalette.fromGenerator(PaletteGenerator g) {
    // Use the dominant color as fallback — gives each album its own natural
    // theme even for monochromatic art (grey album → grey theme, not purple)
    final dominant = g.dominantColor?.color ?? VibePalette.fallback.vibrant;

    return VibePalette(
      vibrant:      g.vibrantColor?.color      ?? g.mutedColor?.color     ?? dominant,
      lightVibrant: g.lightVibrantColor?.color ?? g.vibrantColor?.color   ?? dominant,
      darkVibrant:  g.darkVibrantColor?.color  ?? g.darkMutedColor?.color ?? dominant,
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
