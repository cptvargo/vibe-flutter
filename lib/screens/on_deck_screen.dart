import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../services/on_deck_service.dart';
import '../services/recently_played_service.dart';
import '../theme/vibe_theme.dart';

class OnDeckScreen extends ConsumerStatefulWidget {
  const OnDeckScreen({super.key});

  @override
  ConsumerState<OnDeckScreen> createState() => _OnDeckScreenState();
}

class _OnDeckScreenState extends ConsumerState<OnDeckScreen> {
  List<_GridEntry>          _entries    = [];
  StreamSubscription<void>? _deckSub;
  StreamSubscription<void>? _recentSub;

  @override
  void initState() {
    super.initState();
    _rebuild();
    _deckSub   = OnDeckService.updated.listen((_) { if (mounted) _rebuild(); });
    _recentSub = RecentlyPlayedService.stream.listen((_) { if (mounted) _rebuild(); });
  }

  @override
  void dispose() {
    _deckSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  void _rebuild() {
    final sessions   = OnDeckService.getAllSessions();
    final sessionIds = sessions.map((s) => s.albumId).toSet();

    final entries = <_GridEntry>[];
    for (final s in sessions) {
      entries.add(_GridEntry(
        albumId:    s.albumId,
        albumTitle: s.albumTitle,
        artist:     s.artist,
        artUrl:     s.artUrl,
        progress:   s.progressFraction,
        session:    s,
      ));
    }
    // Fill remaining from recently played, excluding sessions.
    final seenIds = <String>[];
    final recent  = <String, VibeTrack>{};
    for (final t in RecentlyPlayedService.tracks) {
      final aid = t.albumId;
      if (aid == null || aid.isEmpty) continue;
      if (!recent.containsKey(aid)) {
        seenIds.add(aid);
        recent[aid] = t;
      }
    }
    for (final aid in seenIds) {
      if (sessionIds.contains(aid)) continue;
      final t = recent[aid]!;
      entries.add(_GridEntry(
        albumId:    aid,
        albumTitle: t.album,
        artist:     t.artist,
        artUrl:     t.artworkUrl,
        progress:   null,
        session:    null,
      ));
      if (entries.length >= 27) break;
    }

    setState(() => _entries = entries);
  }

  Future<void> _resume(AlbumSession session) async {
    if (!mounted) return;
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    try {
      final result = await JellyfinApi.getAlbumTracks(session.albumId);
      final tracks = ((result['Items'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VibeTrack.fromJellyfin)
          .toList();
      if (tracks.isEmpty) return;
      final idx = session.queueIndex.clamp(0, tracks.length - 1);
      await ref.read(audioHandlerProvider).playTracks(
        tracks,
        startIndex:      idx,
        startPositionMs: session.trackPositionMs,
      );
    } catch (e) {
      debugPrint('OnDeckScreen resume error: $e');
    }
  }

  Future<void> _playFromStart(String albumId) async {
    if (!mounted) return;
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    try {
      final result = await JellyfinApi.getAlbumTracks(albumId);
      final tracks = ((result['Items'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VibeTrack.fromJellyfin)
          .toList();
      if (tracks.isEmpty) return;
      await ref.read(audioHandlerProvider).playTracks(tracks);
    } catch (e) {
      debugPrint('OnDeckScreen play error: $e');
    }
  }

  void _tap(_GridEntry entry) {
    if (entry.session != null) {
      _resume(entry.session!);
    } else {
      context.push(
        '/album/${entry.albumId}'
        '?name=${Uri.encodeComponent(entry.albumTitle)}'
        '&artist=${Uri.encodeComponent(entry.artist)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final top   = MediaQuery.of(context).padding.top;

    final featured  = _entries.isNotEmpty ? _entries.first : null;
    final rest       = _entries.length > 1 ? _entries.sublist(1) : <_GridEntry>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: top + 56,
              child: Padding(
                padding: EdgeInsets.only(top: top, left: 8, right: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const Expanded(
                      child: Text(
                        'On Deck',
                        style: TextStyle(
                          color:      Colors.white,
                          fontSize:   20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Featured card ─────────────────────────────────────────────────
          if (featured != null)
            SliverToBoxAdapter(
              child: _FeaturedCard(
                entry: featured,
                theme: theme,
                onResume:    () => _resume(featured.session!),
                onPlayStart: () => _playFromStart(featured.albumId),
                onViewAlbum: () => context.push(
                  '/album/${featured.albumId}'
                  '?name=${Uri.encodeComponent(featured.albumTitle)}'
                  '&artist=${Uri.encodeComponent(featured.artist)}',
                ),
              ),
            ),

          // ── Grid of remaining entries ─────────────────────────────────────
          if (rest.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  rest.any((e) => e.session != null) ? 'Also In Progress' : 'Recently Played',
                  style: TextStyle(
                    color:      theme.textColor,
                    fontSize:   16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:   3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing:  10,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _GridCard(
                    entry: rest[i],
                    theme: theme,
                    onTap: () => _tap(rest[i]),
                  ),
                  childCount: rest.length,
                ),
              ),
            ),
          ],

          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 100,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry model ───────────────────────────────────────────────────────────────

class _GridEntry {
  final String        albumId;
  final String        albumTitle;
  final String        artist;
  final String        artUrl;
  final double?       progress;
  final AlbumSession? session;
  const _GridEntry({
    required this.albumId,
    required this.albumTitle,
    required this.artist,
    required this.artUrl,
    required this.progress,
    required this.session,
  });
}

// ── Featured card ─────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final _GridEntry   entry;
  final VibeTheme    theme;
  final VoidCallback onResume;
  final VoidCallback onPlayStart;
  final VoidCallback onViewAlbum;

  const _FeaturedCard({
    required this.entry,
    required this.theme,
    required this.onResume,
    required this.onPlayStart,
    required this.onViewAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final w   = MediaQuery.of(context).size.width;
    final art = entry.artUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Blurred background art
            if (art.isNotEmpty)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                  child: CachedNetworkImage(
                    imageUrl:    art,
                    fit:         BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox(),
                  ),
                ),
              ),
            // Dark overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin:  Alignment.topCenter,
                    end:    Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(0x99),
                      Colors.black.withAlpha(0xEE),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Large square art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: art.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl:    art,
                            width:       w - 80,
                            height:      w - 80,
                            fit:         BoxFit.cover,
                            errorWidget: (_, _, _) => _artFallback(w - 80),
                          )
                        : _artFallback(w - 80),
                  ),
                  const SizedBox(height: 16),
                  // Album info
                  Text(
                    entry.albumTitle,
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   20,
                      fontWeight: FontWeight.w700,
                      height:     1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.artist,
                    style: TextStyle(
                      color:    Colors.white.withAlpha(0xAA),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.progress != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value:           entry.progress,
                        minHeight:       4,
                        backgroundColor: Colors.white.withAlpha(0x22),
                        valueColor:      AlwaysStoppedAnimation(theme.accent),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      if (entry.session != null) ...[
                        Expanded(
                          child: _ActionButton(
                            label:    'Resume',
                            icon:     Icons.play_arrow_rounded,
                            accent:   theme.accent,
                            onTap:    onResume,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            label:  'View Album',
                            icon:   Icons.album_rounded,
                            accent: theme.accent,
                            filled: false,
                            onTap:  onViewAlbum,
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: _ActionButton(
                            label:  'Play',
                            icon:   Icons.play_arrow_rounded,
                            accent: theme.accent,
                            onTap:  onPlayStart,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ActionButton(
                            label:  'View Album',
                            icon:   Icons.album_rounded,
                            accent: theme.accent,
                            filled: false,
                            onTap:  onViewAlbum,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artFallback(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color:        theme.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.album_rounded, color: theme.textFaint, size: 64),
  );
}

class _ActionButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    accent;
  final bool     filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color:        filled ? accent.withAlpha(0xEE) : Colors.white.withAlpha(0x18),
          borderRadius: BorderRadius.circular(24),
          border:       filled ? null : Border.all(color: Colors.white.withAlpha(0x33)),
          boxShadow:    filled ? [BoxShadow(color: accent.withAlpha(0x44), blurRadius: 10)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label,
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid card ─────────────────────────────────────────────────────────────────

class _GridCard extends StatelessWidget {
  final _GridEntry   entry;
  final VibeTheme    theme;
  final VoidCallback onTap;

  const _GridCard({
    required this.entry,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: entry.artUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl:    entry.artUrl,
                          fit:         BoxFit.cover,
                          errorWidget: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                if (entry.progress != null)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft:  Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value:           entry.progress,
                        minHeight:       3,
                        backgroundColor: Colors.black.withAlpha(0x66),
                        valueColor:      AlwaysStoppedAnimation(theme.accent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(
            entry.albumTitle,
            style: TextStyle(
              color:      theme.textColor,
              fontSize:   11,
              fontWeight: FontWeight.w600,
              height:     1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            entry.artist,
            style: TextStyle(
              color:    theme.textFaint,
              fontSize: 10,
              height:   1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    decoration: BoxDecoration(
      color:        theme.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.album_rounded, color: theme.textFaint, size: 28),
  );
}
