import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_models.dart';

class FireMixService {
  static const _key = 'fire_mix_tracks_v1';

  static Future<List<VibeTrack>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return VibeTrack(
        id:         m['id'] as String,
        url:        m['url'] as String,
        title:      m['title'] as String,
        artist:     m['artist'] as String,
        album:      m['album'] as String? ?? '',
        albumId:    m['albumId'] as String?,
        artworkUrl: m['artworkUrl'] as String,
        colorUrl:   m['colorUrl'] as String,
        blurHash:   m['blurHash'] as String?,
        duration:   Duration(microseconds: m['durationMicros'] as int? ?? 0),
        raw:        {},
      );
    }).toList();
  }

  static Future<void> save(List<VibeTrack> tracks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, tracks.map((t) => jsonEncode({
      'id':             t.id,
      'url':            t.url,
      'title':          t.title,
      'artist':         t.artist,
      'album':          t.album,
      'albumId':        t.albumId,
      'artworkUrl':     t.artworkUrl,
      'colorUrl':       t.colorUrl,
      'blurHash':       t.blurHash,
      'durationMicros': t.duration.inMicroseconds,
    })).toList());
  }
}
