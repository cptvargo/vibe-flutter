import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PresetMixArtService {
  static const _keyPrefix = 'mix_art_path_';

  static Future<String?> getArtPath(String mixId) async {
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString('$_keyPrefix$mixId');
    if (path == null) return null;
    if (!await File(path).exists()) {
      await prefs.remove('$_keyPrefix$mixId');
      return null;
    }
    return path;
  }

  static Future<String> saveArt(String mixId, Uint8List bytes) async {
    final dir    = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/mix_art');
    await folder.create(recursive: true);
    final file   = File('${folder.path}/$mixId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    final prefs  = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$mixId', file.path);
    return file.path;
  }

  static Future<void> clearArt(String mixId) async {
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString('$_keyPrefix$mixId');
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await prefs.remove('$_keyPrefix$mixId');
  }
}
