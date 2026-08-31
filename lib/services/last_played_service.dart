import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a single MediaItem snapshot so the mini player can be restored on
/// cold start without network access. Does NOT track position — On Deck handles
/// full session persistence.
class LastPlayedService {
  static const _key = 'vibe_last_played_v1';

  static Future<void> save(MediaItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({
        'id':       item.id,
        'title':    item.title,
        'artist':   item.artist,
        'album':    item.album,
        'artUri':   item.artUri?.toString(),
        'duration': item.duration?.inMicroseconds,
        'extras':   item.extras,
      }));
    } catch (_) {}
  }

  static Future<MediaItem?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key);
      if (raw == null) return null;
      final map       = jsonDecode(raw) as Map<String, dynamic>;
      final durMicros = map['duration'] as int?;
      return MediaItem(
        id:       map['id']     as String,
        title:    map['title']  as String,
        artist:   map['artist'] as String?,
        album:    map['album']  as String?,
        artUri:   map['artUri'] != null ? Uri.parse(map['artUri'] as String) : null,
        duration: durMicros != null ? Duration(microseconds: durMicros) : null,
        extras:   (map['extras'] as Map?)?.cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }
}
