import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/vibe_config.dart';

final supabase = Supabase.instance.client;

class AuthService {
  // Current session
  static Session? get session => supabase.auth.currentSession;
  static User?    get user    => supabase.auth.currentUser;
  static bool     get isLoggedIn => user != null;

  // Sign up with email + password (managed server — yours)
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return supabase.auth.signUp(
      email:    email,
      password: password,
      data:     {'display_name': displayName},
    );
  }

  // Sign in with email + password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return supabase.auth.signInWithPassword(
      email:    email,
      password: password,
    );
  }

  // Sign out
  static Future<void> signOut() => supabase.auth.signOut();

  // Password reset email
  static Future<void> resetPassword(String email) =>
      supabase.auth.resetPasswordForEmail(email);

  // Fetch the current user's profile
  static Future<Map<String, dynamic>?> getProfile() async {
    if (user == null) return null;
    final res = await supabase
        .from('profiles')
        .select()
        .eq('id', user!.id)
        .maybeSingle();
    return res;
  }

  // Update profile fields
  static Future<void> updateProfile(Map<String, dynamic> data) async {
    if (user == null) return;
    await supabase.from('profiles').update(data).eq('id', user!.id);
  }

  // Validate an invite code (does not consume it — call consumeInviteCode after account creation)
  static Future<Map<String, dynamic>?> redeemInviteCode(String code) async {
    final res = await supabase
        .from('invite_codes')
        .select('*, servers(*)')
        .eq('code', code.toUpperCase())
        .gt('uses_remaining', 0)
        .maybeSingle();
    return res;
  }

  // Sign up via invite code: creates account, stores server_url, decrements code usage
  static Future<AuthResponse> signUpWithInviteCode({
    required String email,
    required String password,
    required String displayName,
    required Map<String, dynamic> inviteData,
  }) async {
    final server    = inviteData['servers'] as Map<String, dynamic>?;
    final serverUrl = (server?['server_url'] as String?) ?? VibeConfig.serverUrl;
    final inviteId  = inviteData['id'] as String;

    final res = await supabase.auth.signUp(
      email:    email,
      password: password,
      data:     {'display_name': displayName},
    );

    if (res.user != null) {
      // Attach the server URL to this user's profile (best-effort — session may not be active yet)
      try {
        await supabase.from('profiles').update({
          'server_url': serverUrl,
        }).eq('id', res.user!.id);
      } catch (_) {}

      // Decrement uses_remaining — fire-and-forget, don't block sign-in on this
      supabase.rpc('decrement_invite_uses', params: {'invite_id': inviteId}).catchError((_) {});
    }

    return res;
  }

  // Sign up with own server (public path)
  // Server registration is deferred to ensureServerRegistered() after auth is active.
  static Future<AuthResponse> signUpWithServer({
    required String email,
    required String password,
    required String displayName,
    required String serverUrl,
  }) async {
    final res = await supabase.auth.signUp(
      email:    email,
      password: password,
      data:     {'display_name': displayName, 'server_url': serverUrl},
    );

    // Store server_url in user metadata so ensureServerRegistered() can pick it up
    // after the session is established. We avoid writing to DB here because the
    // session may not be active yet (RLS would reject it).
    return res;
  }

  // Ensure the user has a server entry — silently registers if missing.
  // Called from SettingsScreen after auth is fully active.
  static Future<void> ensureServerRegistered() async {
    if (user == null) return;
    final existing = await getMyServer();
    if (existing != null) return;

    // Priority: profile DB value → user metadata (set at signup) → VibeConfig fallback
    final profile     = await getProfile();
    final metaUrl     = user!.userMetadata?['server_url'] as String?;
    final serverUrl   = (profile?['server_url'] as String?)?.isNotEmpty == true
        ? profile!['server_url'] as String
        : metaUrl?.isNotEmpty == true
            ? metaUrl!
            : VibeConfig.serverUrl;

    // Also backfill the profile server_url if it wasn't set during signup
    if ((profile?['server_url'] as String?)?.isEmpty != false) {
      await supabase.from('profiles').update({'server_url': serverUrl}).eq('id', user!.id);
    }

    final name = Uri.tryParse(serverUrl)?.host ?? serverUrl;
    await supabase.from('servers').insert({
      'owner_id':    user!.id,
      'server_url':  serverUrl,
      'server_name': name,
    });
  }

  // Generate an invite code for the current user's server
  static Future<String?> generateInviteCode(String serverId) async {
    if (user == null) return null;
    final code = _randomCode();
    await supabase.from('invite_codes').insert({
      'code':            code,
      'server_id':       serverId,
      'created_by':      user!.id,
      'uses_remaining':  10,
    });
    return code;
  }

  // Register your server so you can generate invite codes
  static Future<String?> registerServer({
    required String serverUrl,
    required String serverName,
  }) async {
    if (user == null) return null;
    final res = await supabase.from('servers').insert({
      'owner_id':    user!.id,
      'server_url':  serverUrl,
      'server_name': serverName,
    }).select().single();
    return res['id'] as String?;
  }

  // Get current user's server registration
  static Future<Map<String, dynamic>?> getMyServer() async {
    if (user == null) return null;
    return supabase
        .from('servers')
        .select()
        .eq('owner_id', user!.id)
        .maybeSingle();
  }

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final suffix = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'VIBE-$suffix';
  }

  // Which Jellyfin server should this user connect to?
  // Returns the managed server URL or a custom one stored in their profile
  static Future<String> resolveServerUrl() async {
    final profile = await getProfile();
    return profile?['server_url'] as String? ?? VibeConfig.serverUrl;
  }
}
