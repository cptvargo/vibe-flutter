import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_models.dart';

class RecentlyPlayedService {
  static const _key        = 'vibe_recently_played';
  static const _aiKey      = 'vibe_ai_recently_played';
  static const _migratedKey = 'vibe_rp_migrated_v3'; // bump to force re-clear
  static const _maxTracks  = 30;

  static final _notifier = _RecentlyPlayedNotifier();
  static Stream<List<VibeTrack>> get stream   => _notifier.stream;
  static Stream<List<VibeTrack>> get aiStream => _notifier.aiStream;
  static List<VibeTrack>         get tracks   => _notifier.tracks;
  static List<VibeTrack>         get aiTracks => _notifier.aiTracks;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // One-time migration: wipe pre-isAI history that has no separation guarantee.
    if (prefs.getBool(_migratedKey) != true) {
      await prefs.remove(_key);
      await prefs.remove(_aiKey);
      await prefs.setBool(_migratedKey, true);
      return; // start with clean slate
    }

    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = (json.decode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(VibeTrack.fromJson)
            // Only keep tracks that are explicitly NOT AI.
            // Tracks with no isAI field default to false — but if any slipped
            // through that are actually AI, the name check below catches them.
            .where((t) => !t.isAI)
            .toList();
        _notifier._set(list, isAI: false);
        // Rewrite cleaned list back so stale entries are purged permanently
        await prefs.setString(_key, json.encode(list.map((t) => t.toJson()).toList()));
      } catch (_) {}
    }

    final aiRaw = prefs.getString(_aiKey);
    if (aiRaw != null) {
      try {
        final list = (json.decode(aiRaw) as List)
            .cast<Map<String, dynamic>>()
            .map(VibeTrack.fromJson)
            .where((t) => t.isAI)
            .toList();
        _notifier._set(list, isAI: true);
        await prefs.setString(_aiKey, json.encode(list.map((t) => t.toJson()).toList()));
      } catch (_) {}
    }
  }

  static Future<void> add(VibeTrack track) async {
    final isAI   = track.isAI;
    final key    = isAI ? _aiKey : _key;
    final current = isAI ? _notifier.aiTracks : _notifier.tracks;

    final updated = [
      track,
      ...current.where((t) => t.id != track.id),
    ].take(_maxTracks).toList();

    _notifier._set(updated, isAI: isAI);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(updated.map((t) => t.toJson()).toList()));
  }
}

class _RecentlyPlayedNotifier {
  final _controller   = StreamController<List<VibeTrack>>.broadcast();
  final _aiController = StreamController<List<VibeTrack>>.broadcast();
  List<VibeTrack> tracks   = [];
  List<VibeTrack> aiTracks = [];

  Stream<List<VibeTrack>> get stream   => _controller.stream;
  Stream<List<VibeTrack>> get aiStream => _aiController.stream;

  void _set(List<VibeTrack> list, {required bool isAI}) {
    if (isAI) {
      aiTracks = list;
      _aiController.add(list);
    } else {
      tracks = list;
      _controller.add(list);
    }
  }
}
