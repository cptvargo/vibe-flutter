import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLandscapeKey = 'vibe_landscape_v1';

/// Manages the landscape mode lock.
///
/// ON  → [DeviceOrientation.landscapeLeft/Right] — wide layout with icon rail.
/// OFF → [DeviceOrientation.portraitUp/Down]     — standard portrait layout.
///
/// Persisted to SharedPreferences so the choice survives app restarts.
class LandscapeModeNotifier extends StateNotifier<bool> {
  LandscapeModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_kLandscapeKey) ?? false;
      if (saved != state) {
        state = saved;
        _applyOrientation(saved);
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    _applyOrientation(state);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kLandscapeKey, state);
    } catch (_) {}
  }

  static void _applyOrientation(bool landscape) {
    SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  }
}

final landscapeModeProvider = StateNotifierProvider<LandscapeModeNotifier, bool>(
  (ref) => LandscapeModeNotifier(),
);
