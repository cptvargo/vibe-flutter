import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vibe_config.dart';

// Runtime Jellyfin credentials — mutable, loaded from Hive on startup.
// VibeConfig values serve as the fallback for the developer's managed server.
class JellyfinConfig {
  static const _boxName = 'jellyfin_cfg';

  static String serverUrl = VibeConfig.serverUrl;
  static String apiKey    = VibeConfig.apiKey;
  static String userId    = VibeConfig.userId;
  static String vibeLib   = VibeConfig.vibeLibrary;
  static String aiLib     = VibeConfig.aiLibrary;

  // True when library IDs come from the managed server (developer).
  // Own-server users have empty library IDs and query all their music.
  static bool get hasAiLib => aiLib.isNotEmpty;

  // Query-string fragment for library filtering — empty string when not set.
  static String get libParam   => vibeLib.isNotEmpty ? '&ParentId=$vibeLib'   : '';
  static String get aiLibParam => aiLib.isNotEmpty   ? '&ParentId=$aiLib'     : '';

  // Load credentials: Hive first (fast), then Supabase metadata (reinstall).
  // Falls back to VibeConfig defaults when neither has credentials.
  static Future<void> load() async {
    final box = await Hive.openBox<String>(_boxName);
    final cached = box.get('serverUrl');
    if (cached != null && cached.isNotEmpty) {
      serverUrl = cached;
      apiKey    = box.get('apiKey')  ?? VibeConfig.apiKey;
      userId    = box.get('userId')  ?? VibeConfig.userId;
      vibeLib   = box.get('vibeLib') ?? '';
      aiLib     = box.get('aiLib')   ?? '';
      return;
    }

    // Hive empty — try Supabase user metadata (covers app reinstall)
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (meta != null) {
      final token  = meta['jellyfin_token']      as String?;
      final uid    = meta['jellyfin_user_id']    as String?;
      final sUrl   = meta['jellyfin_server_url'] as String?;
      if (token != null && token.isNotEmpty &&
          uid   != null && uid.isNotEmpty   &&
          sUrl  != null && sUrl.isNotEmpty) {
        serverUrl = sUrl;
        apiKey    = token;
        userId    = uid;
        vibeLib   = '';
        aiLib     = '';
        // Cache to Hive so next cold-start skips the Supabase round-trip
        await _writeBox(box, sUrl, token, uid, '', '');
        return;
      }
    }

    // Developer fallback — VibeConfig managed-server values (already set as defaults above)
  }

  static Future<void> save({
    required String serverUrl,
    required String apiKey,
    required String userId,
    String vibeLib = '',
    String aiLib   = '',
  }) async {
    JellyfinConfig.serverUrl = serverUrl;
    JellyfinConfig.apiKey    = apiKey;
    JellyfinConfig.userId    = userId;
    JellyfinConfig.vibeLib   = vibeLib;
    JellyfinConfig.aiLib     = aiLib;

    final box = await Hive.openBox<String>(_boxName);
    await _writeBox(box, serverUrl, apiKey, userId, vibeLib, aiLib);
  }

  static Future<void> _writeBox(
    Box<String> box,
    String serverUrl, String apiKey, String userId,
    String vibeLib, String aiLib,
  ) async {
    await box.put('serverUrl', serverUrl);
    await box.put('apiKey',    apiKey);
    await box.put('userId',    userId);
    await box.put('vibeLib',   vibeLib);
    await box.put('aiLib',     aiLib);
  }

  // Called on sign-out — clears Hive and resets to VibeConfig defaults.
  static Future<void> clear() async {
    final box = await Hive.openBox<String>(_boxName);
    await box.clear();
    serverUrl = VibeConfig.serverUrl;
    apiKey    = VibeConfig.apiKey;
    userId    = VibeConfig.userId;
    vibeLib   = VibeConfig.vibeLibrary;
    aiLib     = VibeConfig.aiLibrary;
  }
}
