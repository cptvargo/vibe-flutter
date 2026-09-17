import 'dart:async';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../providers/connection_notifier.dart';
import '../screens/connect_server_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../services/on_deck_service.dart';
import '../services/recently_played_service.dart';
import '../services/vibe_out_service.dart';
import '../theme/palette_service.dart';
import 'top_nav.dart';
import 'mini_player.dart';
import 'desktop_player_bar.dart';

const _kDesktopBreakpoint = 720.0;

const _kBaseTabs = [
  (id: 'home',     label: 'Home',     icon: Icons.home_outlined,          activeIcon: Icons.home_rounded),
  (id: 'search',   label: 'Search',   icon: Icons.search_outlined,        activeIcon: Icons.search),
  (id: 'library',  label: 'Library',  icon: Icons.library_music_outlined, activeIcon: Icons.library_music),
  (id: 'offline',  label: 'Offline',  icon: Icons.offline_pin_outlined,   activeIcon: Icons.offline_pin),
  (id: 'settings', label: 'Settings', icon: Icons.person_outline,         activeIcon: Icons.person_rounded),
];

// In demo mode the Settings tab is replaced with Connect Your Server.
const _kDemoTabs = [
  (id: 'home',    label: 'Home',    icon: Icons.home_outlined,          activeIcon: Icons.home_rounded),
  (id: 'search',  label: 'Search',  icon: Icons.search_outlined,        activeIcon: Icons.search),
  (id: 'library', label: 'Library', icon: Icons.library_music_outlined, activeIcon: Icons.library_music),
  (id: 'offline', label: 'Offline', icon: Icons.offline_pin_outlined,   activeIcon: Icons.offline_pin),
  (id: 'connect', label: 'Connect', icon: Icons.link_outlined,          activeIcon: Icons.link_rounded),
];

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
    final isDemo = ref.read(connectionProvider).isDemoMode;
    if (isDemo) {
      // Snapshot real-user SharedPreferences before clearing so we can restore
      // them exactly when the user exits demo (no demo sessions leak back in).
      OnDeckService.snapshotPreDemo();
      RecentlyPlayedService.snapshotPreDemo();
      OnDeckService.clearForDemo();
      RecentlyPlayedService.clearForDemo();
      VibeOutService.refresh();
    } else {
      VibeOutService.init();
    }
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

  Widget _body(dynamic theme) {
    switch (_activeTab) {
      case 'home':     return const HomeScreen();
      case 'search':   return const SearchScreen();
      case 'library':  return const LibraryScreen();
      case 'offline':  return const DownloadsScreen();
      case 'settings': return const SettingsScreen();
      case 'connect':  return const ConnectServerScreen();
      default:         return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final ambient = ref.watch(ambientThemeProvider);
    final isDemo  = ref.watch(connectionProvider).isDemoMode;
    final tabs    = isDemo ? _kDemoTabs : _kBaseTabs;

    // When the user connects their own server from the Connect tab, demo mode
    // exits (isDemoMode flips false). Re-init services with real credentials
    // and jump to Home so the body doesn't stay stuck on ConnectServerScreen.
    ref.listen<bool>(
      connectionProvider.select((c) => c.isDemoMode),
      (prev, next) {
        if (prev == true && next == false) {
          // Demo → real server: restore pre-demo snapshots (evicts demo sessions),
          // force-refresh ViBE Out with real credentials (bypass demo cache),
          // then jump home so the body doesn't stay stuck on ConnectServerScreen.
          OnDeckService.restorePostDemo();
          RecentlyPlayedService.restorePostDemo();
          VibeOutService.refresh();
          setState(() => _activeTab = 'home');
        }
      },
    );
    final width   = MediaQuery.sizeOf(context).width;

    final ambientGlow = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.8,
              colors: [
                ambient.glowColor.withAlpha(0x1A),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );

    if (width >= _kDesktopBreakpoint) {
      // ── Desktop layout ──────────────────────────────────────────────────────
      return Scaffold(
        backgroundColor: theme.background,
        body: Stack(
          children: [
            ambientGlow,
            Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _DesktopSidebar(
                        activeTab:   _activeTab,
                        tabs:        tabs,
                        onTabChange: (tab) => setState(() => _activeTab = tab),
                        theme:       theme,
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Colors.white.withAlpha(0x0F),
                      ),
                      // Content — centered with max width so it doesn't stretch
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: _body(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Full-width desktop playback bar
                const DesktopPlayerBar(),
              ],
            ),
          ],
        ),
      );
    }

    // ── Mobile layout (unchanged) ─────────────────────────────────────────────
    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          ambientGlow,
          Column(
            children: [
              TopNav(
                activeTab:   _activeTab,
                tabs:        tabs,
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
}

// ── Desktop sidebar ───────────────────────────────────────────────────────────

typedef _TabDef = ({String id, String label, IconData icon, IconData activeIcon});

class _DesktopSidebar extends StatelessWidget {
  final String activeTab;
  final List<_TabDef> tabs;
  final ValueChanged<String> onTabChange;
  final dynamic theme;

  const _DesktopSidebar({
    required this.activeTab,
    required this.tabs,
    required this.onTabChange,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 200,
          color: Colors.black.withAlpha(0x66),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── ViBE wordmark ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'Vi',
                      style: TextStyle(
                        color:       theme.accentBright,
                        fontSize:    28,
                        fontWeight:  FontWeight.w900,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(color: theme.accentBright.withAlpha(0xCC), blurRadius: 4),
                          Shadow(color: theme.accent.withAlpha(0x55), blurRadius: 20),
                        ],
                      ),
                    ),
                    TextSpan(
                      text: 'BE',
                      style: TextStyle(
                        color:       theme.accentBright,
                        fontSize:    28,
                        fontWeight:  FontWeight.w900,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(color: theme.accentBright.withAlpha(0xCC), blurRadius: 4),
                          Shadow(color: theme.accent.withAlpha(0x55), blurRadius: 20),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Nav items ───────────────────────────────────────────────────
              ...tabs.map((tab) {
                final isActive = activeTab == tab.id;
                final color = isActive
                    ? theme.accentBright
                    : theme.accentBright.withAlpha(0x66);

                return GestureDetector(
                  onTap: () => onTabChange(tab.id),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.accentBright.withAlpha(0x18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isActive
                          ? Border.all(color: theme.accentBright.withAlpha(0x22))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isActive ? tab.activeIcon : tab.icon,
                          size: 20,
                          color: color,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color:      color,
                            fontSize:   14,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
