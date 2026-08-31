import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/album_screen.dart';
import '../screens/all_artists_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/login_screen.dart';
import '../screens/mix_picker_screen.dart';
import '../screens/on_deck_screen.dart';
import '../screens/player_screen.dart';
import '../screens/song_link_screen.dart';
import '../screens/reset_password_screen.dart';
import '../widgets/main_shell.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: authNotifier,
  redirect: (context, state) {
    final loggedIn  = authNotifier.isLoggedIn;
    final atLogin   = state.matchedLocation == '/login';
    final atReset   = state.matchedLocation == '/reset-password';

    if (authNotifier.isPasswordRecovery) return '/reset-password';
    if (!loggedIn && !atLogin) return '/login';
    if (loggedIn  &&  atLogin) return '/';
    if (!authNotifier.isPasswordRecovery && atReset) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    GoRoute(
      path: '/reset-password',
      builder: (context, state) => const ResetPasswordScreen(),
    ),

    // Root shell — album/artist/mix are nested so router.go('/album/:id')
    // resolves to [MainShell, TargetScreen], giving a proper back stack.
    GoRoute(
      path: '/',
      builder: (context, state) => const MainShell(),
      routes: [
        GoRoute(
          path: 'artist/:id',
          builder: (context, state) => ArtistScreen(
            artistId:   state.pathParameters['id']!,
            artistName: state.uri.queryParameters['name'] ?? '',
          ),
        ),
        GoRoute(
          path: 'album/:id',
          builder: (context, state) => AlbumScreen(
            albumId:    state.pathParameters['id']!,
            albumName:  state.uri.queryParameters['name']   ?? '',
            artistName: state.uri.queryParameters['artist'] ?? '',
            year:       int.tryParse(state.uri.queryParameters['year'] ?? ''),
          ),
        ),
        GoRoute(
          path: 'mix/:type',
          builder: (context, state) => MixPickerScreen(
            type: state.pathParameters['type']!,
          ),
        ),
        GoRoute(
          path: 'all-artists',
          builder: (context, state) => const AllArtistsScreen(),
        ),
        GoRoute(
          path: 'on-deck',
          builder: (context, state) => const OnDeckScreen(),
        ),
      ],
    ),

    // Deep link: vibemusic://song/{id} — opened from a ViBE Out share card.
    GoRoute(
      path: '/song/:id',
      builder: (context, state) => SongLinkScreen(
        trackId: state.pathParameters['id']!,
        title:   state.uri.queryParameters['title']  ?? '',
        artist:  state.uri.queryParameters['artist'] ?? '',
      ),
    ),

    // Player stays at root level — it's a full-screen modal overlay, not a
    // sub-page of MainShell, and must be reachable from any route.
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        opaque: false,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        child: const PlayerScreen(),
        transitionsBuilder: (context, animation, _, child) {
          final slide = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic))
              .animate(animation);
          final fade = Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(
                  curve: const Interval(0.0, 0.4, curve: Curves.easeIn)))
              .animate(animation);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    ),
  ],
);
