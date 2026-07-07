import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'audio/audio_handler.dart';
import 'config/vibe_config.dart';
import 'navigation/router.dart';
import 'theme/palette_service.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only — music apps don't need landscape
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Draw edge-to-edge (content behind status bar / nav bar)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // White status bar icons — matches our dark UI on both platforms
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:             Colors.transparent,
    statusBarIconBrightness:    Brightness.light,  // Android: white icons
    statusBarBrightness:        Brightness.dark,   // iOS: white icons
    systemNavigationBarColor:   Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await Supabase.initialize(
    url:            VibeConfig.supabaseUrl,
    publishableKey: VibeConfig.supabaseAnon,
  );

  await PaletteService.init();

  final handler = await AudioService.init(
    builder: () => VibeAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId:   'com.playvibemusic.vibe.audio',
      androidNotificationChannelName: 'Vibe',
      androidNotificationOngoing:     false,
      androidStopForegroundOnPause:   true,
    ),
  );

  // Configure audio session for music playback on both platforms.
  // On iOS this sets AVAudioSessionCategoryPlayback (plays in background,
  // pauses correctly on calls/Siri). On Android it requests audio focus.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(handler)],
      child: const VibeApp(),
    ),
  );
}

class VibeApp extends ConsumerWidget {
  const VibeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title:                      'Vibe',
      debugShowCheckedModeBanner: false,
      routerConfig:               router,
      // Bouncing scroll physics everywhere — matches the iOS feel
      // even on Android. Makes lists feel premium rather than abrupt.
      scrollBehavior:             const _VibeScrollBehavior(),
      theme: ThemeData(
        brightness:              Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(primary: const Color(0xFF7C3AED)),
      ),
    );
  }
}

// Bouncing physics on every platform — the iOS feel we want for a music app
class _VibeScrollBehavior extends ScrollBehavior {
  const _VibeScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
