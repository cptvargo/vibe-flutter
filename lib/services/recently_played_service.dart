import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_models.dart';

class RecentlyPlayedService {
  static const _key      = 'vibe_recently_played';
  static const _maxTracks = 30;

  static final _notifier = _RecentlyPlayedNotifier();
  static Stream<List<VibeTrack>> get stream => _notifier.stream;
  static List<VibeTrack>         get tracks => _notifier.tracks;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = (json.decode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(VibeTrack.fromJson)
          .toList();
      _notifier._set(list);
    } catch (_) {}
  }

  static Future<void> add(VibeTrack track) async {
    final updated = [
      track,
      ..._notifier.tracks.where((t) => t.id != track.id),
    ].take(_maxTracks).toList();

    _notifier._set(updated);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(updated.map((t) => t.toJson()).toList()));
  }
}

class _RecentlyPlayedNotifier {
  final _controller = StreamController<List<VibeTrack>>.broadcast();
  List<VibeTrack> tracks = [];

  Stream<List<VibeTrack>> get stream => _controller.stream;

  void _set(List<VibeTrack> list) {
    tracks = list;
    _controller.add(list);
  }
}
