import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_service.dart';
import '../api/jellyfin_models.dart';

class OfflinePlaylistService {
  static const _boxName = 'vibe_offline_playlists_v1';
  static Box<Map>? _box;

  static final _onChange = StreamController<void>.broadcast();
  static Stream<void> get onChange => _onChange.stream;

  static Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> getPlaylists() {
    return (_box?.values ?? [])
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
      ..sort((a, b) {
        final ac = a['createdAt'] as String? ?? '';
        final bc = b['createdAt'] as String? ?? '';
        return ac.compareTo(bc);
      });
  }

  static Map<String, dynamic>? getPlaylist(String id) {
    final raw = _box?.get(id);
    return raw != null ? Map<String, dynamic>.from(raw) : null;
  }

  static List<VibeTrack> getPlaylistTracks(String playlistId) {
    final data = getPlaylist(playlistId);
    if (data == null) return [];
    final ids = List<String>.from(data['trackIds'] as List? ?? []);
    return ids
        .map((id) {
          final d = DownloadService.getDownloadData(id);
          return d != null ? DownloadService.trackFromData(d) : null;
        })
        .whereType<VibeTrack>()
        .toList();
  }

  static int trackCount(String playlistId) {
    final data = getPlaylist(playlistId);
    if (data == null) return 0;
    return (data['trackIds'] as List?)?.length ?? 0;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  static Future<String> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _box?.put(id, {
      'id':        id,
      'name':      name,
      'trackIds':  <String>[],
      'createdAt': DateTime.now().toIso8601String(),
    });
    _onChange.add(null);
    return id;
  }

  static Future<void> renamePlaylist(String id, String name) async {
    final data = getPlaylist(id);
    if (data == null) return;
    data['name'] = name;
    await _box?.put(id, data);
    _onChange.add(null);
  }

  static Future<void> deletePlaylist(String id) async {
    await _box?.delete(id);
    _onChange.add(null);
  }

  static Future<void> addTrack(String playlistId, String itemId) async {
    final data = getPlaylist(playlistId);
    if (data == null) return;
    final ids = List<String>.from(data['trackIds'] as List? ?? []);
    if (!ids.contains(itemId)) {
      ids.add(itemId);
      data['trackIds'] = ids;
      await _box?.put(playlistId, data);
      _onChange.add(null);
    }
  }

  static Future<void> removeTrack(String playlistId, String itemId) async {
    final data = getPlaylist(playlistId);
    if (data == null) return;
    final ids = List<String>.from(data['trackIds'] as List? ?? []);
    if (ids.remove(itemId)) {
      data['trackIds'] = ids;
      await _box?.put(playlistId, data);
      _onChange.add(null);
    }
  }
}
