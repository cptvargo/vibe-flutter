import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ArtistMixEntry {
  final String  id;
  final String  name;
  final String? imageTag;
  const ArtistMixEntry({required this.id, required this.name, this.imageTag});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'imageTag': imageTag};

  factory ArtistMixEntry.fromJson(Map<String, dynamic> j) => ArtistMixEntry(
        id:       j['id']       as String,
        name:     j['name']     as String,
        imageTag: j['imageTag'] as String?,
      );
}

class ArtistMixService {
  static const _key = 'artist_mix_v1';

  static Future<List<ArtistMixEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => ArtistMixEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<ArtistMixEntry> artists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, artists.map((a) => jsonEncode(a.toJson())).toList());
  }
}
