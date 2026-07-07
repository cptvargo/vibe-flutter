import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/palette_service.dart';
import 'top_nav.dart';
import 'mini_player.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  String _activeTab = 'home';
  StreamSubscription<MediaItem?>? _mediaSub;

  @override
  void initState() {
    super.initState();
    // Start listening after the first frame so providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenToTrackChanges());
  }

  void _listenToTrackChanges() {
    final handler = ref.read(audioHandlerProvider);
    _mediaSub = handler.mediaItem.listen((item) async {
      if (!mounted || item == null) return;
      final colorUrl = item.extras?['colorUrl'] as String?;
      if (colorUrl == null || colorUrl.isEmpty) return;
      final palette = await PaletteService.extractFromUrl(colorUrl, item.id);
      if (palette != null && mounted) {
        ref.read(paletteProvider.notifier).state = palette;
      }
    });
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          Column(
            children: [
              TopNav(
                activeTab: _activeTab,
                onTabChange: (tab) => setState(() => _activeTab = tab),
              ),
              Expanded(child: _body(theme)),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }

  Widget _body(dynamic theme) {
    switch (_activeTab) {
      case 'home':    return const HomeScreen();
      case 'search':  return const SearchScreen();
      case 'library': return const LibraryScreen();
      case 'ai':       return Center(child: Text('AI Music coming soon',
                           style: TextStyle(color: theme.textDim, fontSize: 15)));
      case 'settings': return const SettingsScreen();
      default:         return const HomeScreen();
    }
  }
}
