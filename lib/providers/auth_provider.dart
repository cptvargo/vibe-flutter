import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/jellyfin_config.dart';
import '../services/auth_service.dart';

// Simple ChangeNotifier that fires whenever Supabase auth state changes.
// Passed to GoRouter.refreshListenable so the router re-evaluates redirects
// on every sign-in / sign-out.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    _sub = supabase.auth.onAuthStateChange.listen((state) {
      _isPasswordRecovery = state.event == AuthChangeEvent.passwordRecovery;
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.tokenRefreshed) {
        // Load Jellyfin credentials from Hive → Supabase metadata.
        // Non-blocking: the home screen will retry on any API error.
        JellyfinConfig.load();
      } else if (state.event == AuthChangeEvent.signedOut) {
        JellyfinConfig.clear();
      }
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;
  bool _isPasswordRecovery = false;

  bool get isLoggedIn         => supabase.auth.currentSession != null;
  bool get isPasswordRecovery => _isPasswordRecovery;

  void clearPasswordRecovery() {
    _isPasswordRecovery = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// Singleton kept alive for the lifetime of the app so the router can
// hold a reference to the same object without a ProviderScope.
final authNotifier = AuthNotifier();

// Riverpod provider — screens that need to react to auth state watch this.
final authProvider = ChangeNotifierProvider<AuthNotifier>((_) => authNotifier);
