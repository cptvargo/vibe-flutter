import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

typedef _TabDef = ({String id, String label, IconData icon, IconData activeIcon});

class TopNav extends ConsumerWidget {
  final String activeTab;
  final List<_TabDef> tabs;
  final ValueChanged<String> onTabChange;

  const TopNav({super.key, required this.activeTab, required this.tabs, required this.onTabChange});

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
            child: _NavRow(theme: theme, activeTab: activeTab, tabs: tabs, onTabChange: onTabChange),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final VibeTheme theme;
  final String activeTab;
  final List<_TabDef> tabs;
  final ValueChanged<String> onTabChange;

  const _NavRow({required this.theme, required this.activeTab, required this.tabs, required this.onTabChange});

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
                  color: theme.accentBright,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [
                    // Tight at-surface light — the letters themselves are the source
                    Shadow(color: theme.accentBright.withAlpha(0xCC), blurRadius: 4),
                    // Wider ambient spill — light bleeding onto the surface behind
                    Shadow(color: theme.accent.withAlpha(0x55), blurRadius: 20),
                  ],
                ),
              ),
              TextSpan(
                text: 'BE',
                style: TextStyle(
                  color: theme.accentBright,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
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
        // Tabs
        ...tabs.map((tab) {
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
