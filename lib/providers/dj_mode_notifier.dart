import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../audio/audio_handler.dart';
import '../providers.dart';

const _kDjModeKey = 'vibe_dj_mode_v1';

/// Manages the DJ mode toggle (crossfade on/off).
///
/// DJ mode ON  → [PlaybackMode.crossfade] — smooth equal-power blend (default).
/// DJ mode OFF → [PlaybackMode.none]      — 2.5 s silence gap between tracks.
///
/// The [_onModeChange] callback is injected so the notifier can be tested
/// without a real [VibeAudioHandler]. The provider supplies the real handler.
class DjModeNotifier extends StateNotifier<bool> {
  final void Function(bool djModeOn) _onModeChange;

  DjModeNotifier(this._onModeChange) : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final saved  = prefs.getBool(_kDjModeKey) ?? true;
      if (saved != state) {
        state = saved;
        _onModeChange(saved);
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    _onModeChange(state);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDjModeKey, state);
    } catch (_) {}
  }
}

final djModeProvider = StateNotifierProvider<DjModeNotifier, bool>((ref) {
  final handler = ref.read(audioHandlerProvider);
  return DjModeNotifier((djModeOn) {
    handler.setPlaybackMode(
      djModeOn ? PlaybackMode.crossfade : PlaybackMode.none,
    );
  });
});
