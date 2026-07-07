import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

const _kTabs = [
  (id: 'home',     label: 'Home',     icon: Icons.home_outlined,           activeIcon: Icons.home),
  (id: 'search',   label: 'Search',   icon: Icons.search_outlined,         activeIcon: Icons.search),
  (id: 'library',  label: 'Library',  icon: Icons.library_music_outlined,  activeIcon: Icons.library_music),
  (id: 'ai',       label: 'AI Music', icon: Icons.auto_awesome_outlined,   activeIcon: Icons.auto_awesome),
  (id: 'settings', label: 'Settings', icon: Icons.person_outline,          activeIcon: Icons.person),
];

class TopNav extends ConsumerWidget {
  final String activeTab;
  final ValueChanged<String> onTabChange;

  const TopNav({super.key, required this.activeTab, required this.onTabChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(0x73),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withAlpha(0x0F),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: _NavRow(theme: theme, activeTab: activeTab, onTabChange: onTabChange),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final VibeTheme theme;
  final String activeTab;
  final ValueChanged<String> onTabChange;

  const _NavRow({required this.theme, required this.activeTab, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ViBE logo
        Padding(
          padding: const EdgeInsets.only(left: 18, right: 6, top: 8, bottom: 8),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Vi',
                style: TextStyle(
                  color: theme.accentBright.withAlpha(0xAA),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [Shadow(color: theme.accent, blurRadius: 10)],
                ),
              ),
              TextSpan(
                text: 'BE',
                style: TextStyle(
                  color: theme.accentBright,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [Shadow(color: theme.accent, blurRadius: 10)],
                ),
              ),
            ]),
          ),
        ),
        // Tabs
        ..._kTabs.map((tab) {
          final isActive = activeTab == tab.id;
          final color = isActive
              ? theme.accentBright
              : theme.accentBright.withAlpha(0x66);
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChange(tab.id),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isActive ? tab.activeIcon : tab.icon, size: 18, color: color),
                    const SizedBox(height: 2),
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
