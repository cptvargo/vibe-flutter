import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api/jellyfin_models.dart';
import 'audio/audio_handler.dart';
import 'services/fire_mix_service.dart';
import 'theme/palette_service.dart';
import 'theme/vibe_theme.dart';

// Audio handler — initialized in main.dart and overridden in ProviderScope
final audioHandlerProvider = Provider<VibeAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider must be overridden'),
);

// True while the full player screen is on the navigation stack
final playerOpenProvider = StateProvider<bool>((ref) => false);

// Current palette — updated when track changes
final paletteProvider = StateProvider<VibePalette>((ref) => VibePalette.fallback);

// Current theme — derived from palette
final themeProvider = Provider<VibeTheme>((ref) {
  final palette = ref.watch(paletteProvider);
  return VibeTheme.from(palette);
});

// Fire Mix — tracks the user has marked as fire; persisted to SharedPreferences
class FireMixNotifier extends StateNotifier<List<VibeTrack>> {
  FireMixNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await FireMixService.load();
  }

  Future<void> toggle(VibeTrack track) async {
    final alreadyFired = state.any((t) => t.id == track.id);
    state = alreadyFired
        ? state.where((t) => t.id != track.id).toList()
        : [...state, track];
    await FireMixService.save(state);
  }

  bool contains(String trackId) => state.any((t) => t.id == trackId);
}

final fireMixProvider =
    StateNotifierProvider<FireMixNotifier, List<VibeTrack>>(
  (ref) => FireMixNotifier(),
);
