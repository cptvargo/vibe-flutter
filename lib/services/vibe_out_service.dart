import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';

class VibeOutService {
  static const _tracksKey    = 'vibe_out_tracks_v1';
  static const _refreshedKey = 'vibe_out_refreshed_v1';
  static const _trackCount   = 28;
  static const _refreshDays  = 7;

  static List<VibeTrack> _tracks = [];
  static final _ctrl = StreamController<void>.broadcast();

  static Stream<void> get updated => _ctrl.stream;
  static List<VibeTrack> get tracks => List.unmodifiable(_tracks);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_tracksKey);
    final stamp = prefs.getString(_refreshedKey);

    if (raw != null && stamp != null && !_isStale(stamp)) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        // Regenerate stream URLs with current credentials (handles server/key changes).
        _tracks = list.map((j) {
          j['url'] = JellyfinApi.streamUrl(j['id'] as String);
          return VibeTrack.fromJson(j);
        }).toList();
        if (_tracks.isNotEmpty) return;
      } catch (_) {}
    }
    await _fetch(prefs);
  }

  static bool _isStale(String stamp) {
    final date = DateTime.tryParse(stamp);
    if (date == null) return true;
    return DateTime.now().difference(date).inDays >= _refreshDays;
  }

  static Future<void> refresh() => _fetch(null);

  static Future<void> _fetch(SharedPreferences? prefs) async {
    try {
      prefs ??= await SharedPreferences.getInstance();
      final fresh = await JellyfinApi.getRandomTracks(limit: _trackCount);
      if (fresh.isEmpty) return;
      _tracks = fresh;
      await prefs.setString(
        _tracksKey,
        jsonEncode(fresh.map((t) => t.toJson()).toList()),
      );
      await prefs.setString(_refreshedKey, DateTime.now().toIso8601String());
      _ctrl.add(null);
    } catch (_) {}
  }

  // Swap a single track for a fresh random one — used by "Remove from ViBE Out".
  static Future<void> replaceTrack(String trackId) async {
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx < 0) return;
    try {
      // Fetch a small batch so we can find one not already in the list.
      final candidates = await JellyfinApi.getRandomTracks(limit: 10);
      final usedIds    = _tracks.map((t) => t.id).toSet();
      final pick = candidates.firstWhere(
        (t) => !usedIds.contains(t.id),
        orElse: () => candidates.first,
      );
      _tracks = List.of(_tracks)..[idx] = pick;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _tracksKey,
        jsonEncode(_tracks.map((t) => t.toJson()).toList()),
      );
      _ctrl.add(null);
    } catch (_) {}
  }
}
