import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/mix_picker_screen.dart';
import '../screens/player_screen.dart';
import '../widgets/main_shell.dart';

final GoRouter router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainShell(),
    ),
    GoRoute(
      path: '/artist/:id',
      builder: (context, state) => ArtistScreen(
        artistId:   state.pathParameters['id']!,
        artistName: state.uri.queryParameters['name'] ?? '',
      ),
    ),
    GoRoute(
      path: '/album/:id',
      builder: (context, state) => AlbumScreen(
        albumId:    state.pathParameters['id']!,
        albumName:  state.uri.queryParameters['name']   ?? '',
        artistName: state.uri.queryParameters['artist'] ?? '',
        year:       int.tryParse(state.uri.queryParameters['year'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/mix/:type',
      builder: (context, state) => MixPickerScreen(
        type: state.pathParameters['type']!,
      ),
    ),
    GoRoute(
      path: '/player',
      // Slide up from bottom; opaque:false keeps underlying route rendered
      // so drag-to-dismiss can reveal the page below
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
          // Fade in over the first 40% of the animation for a smooth roll-up feel
          final fade = Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: const Interval(0.0, 0.4, curve: Curves.easeIn)))
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
