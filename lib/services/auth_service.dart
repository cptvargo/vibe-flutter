import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/jellyfin_config.dart';
import '../config/vibe_config.dart';
import '../api/jellyfin_api.dart';

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

  // Password reset email — deep link opens the app to /reset-password
  static Future<void> resetPassword(String email) =>
      supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.playvibemusic.vibe://reset-callback',
      );

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

  // Validate an invite code via SECURITY DEFINER function
  static Future<Map<String, dynamic>?> redeemInviteCode(String code) async {
    final res = await supabase.rpc('validate_invite_code', params: {'p_code': code});
    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  // Sign up via invite code: creates ViBE account linked to the inviting server.
  // Call createJellyfinAccountForInvite() first to get the Jellyfin credentials,
  // then pass them here so they're embedded in ViBE account metadata.
  static Future<AuthResponse> signUpWithInviteCode({
    required String email,
    required String password,
    required String displayName,
    required Map<String, dynamic> inviteData,
    String? jellyfinToken,
    String? jellyfinUserId,
  }) async {
    final server    = inviteData['servers'] as Map<String, dynamic>?;
    final serverUrl = (server?['server_url'] as String?) ?? VibeConfig.serverUrl;
    final inviteId  = inviteData['id'] as String;

    final res = await supabase.auth.signUp(
      email:    email,
      password: password,
      data: {
        'display_name':        displayName,
        'server_url':          serverUrl,
        if (jellyfinToken  != null) 'jellyfin_token':      jellyfinToken,
        if (jellyfinUserId != null) 'jellyfin_user_id':    jellyfinUserId,
        if (jellyfinToken  != null) 'jellyfin_server_url': serverUrl,
      },
    );

    if (res.user != null) {
      try {
        await supabase.from('profiles').update({
          'server_url': serverUrl,
        }).eq('id', res.user!.id);
      } catch (_) {}

      supabase.rpc('decrement_invite_uses', params: {'invite_id': inviteId}).catchError((_) {});
    }

    return res;
  }

  // Calls the create-jellyfin-user edge function to auto-create a Jellyfin
  // account on the inviting server using the owner's stored admin API key.
  // Returns { server_url, jellyfin_user_id, jellyfin_token, invite_id } on success,
  // or throws with a user-readable message on failure.
  static Future<Map<String, dynamic>> createJellyfinAccountForInvite({
    required String inviteCode,
    required String username,
    required String password,
  }) async {
    final res = await supabase.functions.invoke(
      'create-jellyfin-user',
      body: {
        'invite_code': inviteCode,
        'username':    username,
        'password':    password,
      },
    );

    final data = res.data as Map<String, dynamic>?;
    if (res.status != 200 || data == null) {
      final msg = data?['error'] as String? ?? 'Failed to create Jellyfin account.';
      throw Exception(msg);
    }

    return data;
  }

  // Save the admin API key for the owner's server so invited users can
  // get Jellyfin accounts created automatically.
  static Future<void> saveAdminApiKey({
    required String serverId,
    required String apiKey,
  }) async {
    await supabase
        .from('servers')
        .update({'admin_api_key': apiKey.trim()})
        .eq('id', serverId);
  }

  // Sign up with own server: authenticates with Jellyfin first, then creates ViBE account
  static Future<AuthResponse> signUpWithServer({
    required String email,
    required String password,
    required String displayName,
    required String serverUrl,
    required String jellyfinToken,
    required String jellyfinUserId,
  }) async {
    final res = await supabase.auth.signUp(
      email:    email,
      password: password,
      data: {
        'display_name':        displayName,
        'server_url':          serverUrl,
        'jellyfin_token':      jellyfinToken,
        'jellyfin_user_id':    jellyfinUserId,
        'jellyfin_server_url': serverUrl,
      },
    );
    return res;
  }

  // Load Jellyfin credentials into JellyfinConfig.
  // Checks Hive first, then Supabase metadata (covers reinstall).
  static Future<void> loadJellyfinConfig() async {
    await JellyfinConfig.load();
  }

  // Save Jellyfin credentials to Hive + Supabase metadata.
  // Called immediately after a successful Jellyfin authentication.
  static Future<void> saveJellyfinCredentials({
    required String serverUrl,
    required String token,
    required String userId,
  }) async {
    await JellyfinConfig.save(serverUrl: serverUrl, apiKey: token, userId: userId);
    // Persist to Supabase metadata so a reinstall can recover credentials
    try {
      await supabase.auth.updateUser(UserAttributes(
        data: {
          'jellyfin_token':      token,
          'jellyfin_user_id':    userId,
          'jellyfin_server_url': serverUrl,
        },
      ));
    } catch (_) {}
  }

  // Authenticate against a Jellyfin server and configure JellyfinConfig.
  // Returns null on failure (bad URL, wrong credentials, unreachable server).
  static Future<({String token, String userId})?> authenticateJellyfin({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    return JellyfinApi.authenticateByName(
      serverUrl: serverUrl,
      username:  username,
      password:  password,
    );
  }

  // Ensure the user has a server entry — silently registers if missing.
  static Future<void> ensureServerRegistered() async {
    if (user == null) return;
    final existing = await getMyServer();
    if (existing != null) return;

    final profile   = await getProfile();
    final metaUrl   = user!.userMetadata?['server_url'] as String?;
    final serverUrl = (profile?['server_url'] as String?)?.isNotEmpty == true
        ? profile!['server_url'] as String
        : metaUrl?.isNotEmpty == true
            ? metaUrl!
            : VibeConfig.serverUrl;

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

  // Permanently delete the current user's account and all associated data.
  static Future<void> deleteAccount() async {
    if (user == null) return;
    await supabase.rpc('delete_user');
    await supabase.auth.signOut();
  }

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // Which Jellyfin server should this user connect to?
  static Future<String> resolveServerUrl() async {
    final profile = await getProfile();
    return profile?['server_url'] as String? ?? VibeConfig.serverUrl;
  }
}
