import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/reauth_sheet.dart';
import '../providers.dart';
import '../services/preset_mix_service.dart';
import '../services/recently_played_service.dart';
import '../services/on_deck_service.dart';
import '../theme/vibe_theme.dart';
import '../widgets/vibe_out_section.dart';
import '../widgets/vibe_ui.dart';
import 'mix_detail_screen.dart';

const _kAlbumSize = 140.0;

// ─── Deck entry ────────────────────────────────────────────────────────────────
// Lightweight view-model for a single On Deck grid card. Sessions supply a
// progress value and enable resume; recently-played albums show no bar.
class _DeckEntry {
  final String       albumId;
  final String       albumTitle;
  final String       artist;
  final String       artUrl;
  final double?      progress; // null = album not in progress, no bar shown
  final AlbumSession? session; // non-null = can resume

  const _DeckEntry({
    required this.albumId,
    required this.albumTitle,
    required this.artist,
    required this.artUrl,
    required this.progress,
    required this.session,
  });
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {

  List<_DeckEntry>           _deckEntries       = [];
  AlbumSession?              _topSession;
  List<Map<String, dynamic>> _recentAlbums      = [];
  List<Map<String, dynamic>> _artists           = [];
  List<Map<String, dynamic>> _dailyArtistAlbums = [];
  bool                       _loading           = true;
  String?                    _error;

  StreamSubscription<void>?  _deckSub;
  final _deckPageCtrl = PageController();
  int   _deckPage     = 0;

  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _loadDeckData();
    _loadData();
    // Re-build deck when a new track plays (recently played list changes).
    RecentlyPlayedService.stream.listen((_) {
      if (mounted) _loadDeckData();
    });
    // Re-build deck when OnDeckService saves / removes a session.
    _deckSub = OnDeckService.updated.listen((_) {
      if (mounted) _loadDeckData();
    });
  }

  @override
  void dispose() {
    _deckSub?.cancel();
    _deckPageCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  Animation<double> _sec(int i) => CurvedAnimation(
    parent: _enterCtrl,
    curve: Interval(
      (i * 0.12).clamp(0.0, 0.8),
      ((i * 0.12) + 0.55).clamp(0.0, 1.0),
      curve: Curves.easeOut,
    ),
  );

  // ── On Deck data ─────────────────────────────────────────────────────────────

  void _loadDeckData() {
    final sessions   = OnDeckService.getAllSessions();
    final topSession = sessions.isNotEmpty ? sessions.first : null;
    final sessionIds = sessions.map((s) => s.albumId).toSet();

    // Recently played albums not already represented by a session.
    final seenIds        = <String>[];
    final recentByAlbum  = <String, VibeTrack>{};
    for (final t in RecentlyPlayedService.tracks) {
      final aid = t.albumId;
      if (aid == null || aid.isEmpty) continue;
      if (!recentByAlbum.containsKey(aid)) {
        seenIds.add(aid);
        recentByAlbum[aid] = t;
      }
    }

    // Quick lookup from already-fetched library data (27 most recently added).
    final albumNameById = <String, String>{
      for (final a in _recentAlbums)
        if ((a['Id'] as String?)?.isNotEmpty == true)
          a['Id'] as String: (a['Name'] as String? ?? ''),
    };

    final entries       = <_DeckEntry>[];
    final staleSessions = <String>[]; // albumIds that still need a network patch

    // Sessions first — ordered most-recent first by OnDeckService.
    for (final s in sessions) {
      String title = s.albumTitle.isNotEmpty
          ? s.albumTitle
          : (albumNameById[s.albumId] ?? '');
      if (title.isEmpty) staleSessions.add(s.albumId);
      entries.add(_DeckEntry(
        albumId:    s.albumId,
        albumTitle: title,
        artist:     s.artist,
        artUrl:     s.artUrl,
        progress:   s.progressFraction,
        session:    s,
      ));
    }

    // Fire-and-forget: fetch album names for stale sessions not covered by the
    // local lookup, persist them so the fix is permanent, then refresh the UI.
    if (staleSessions.isNotEmpty) _patchStaleTitles(staleSessions);
    // Then recently played (no progress bar — not currently in progress).
    for (final aid in seenIds) {
      if (sessionIds.contains(aid)) continue;
      final t = recentByAlbum[aid]!;
      entries.add(_DeckEntry(
        albumId:    aid,
        albumTitle: t.album,
        artist:     t.artist,
        artUrl:     t.artworkUrl,
        progress:   null,
        session:    null,
      ));
      if (entries.length >= 27) break;
    }
    // Fill any remaining slots from the library (recently added albums).
    // This ensures the grid is populated even before the user has played much.
    if (entries.length < 27 && _recentAlbums.isNotEmpty) {
      final usedIds = entries.map((e) => e.albumId).toSet();
      for (final a in _recentAlbums) {
        if (entries.length >= 27) break;
        final aid    = a['Id']          as String? ?? '';
        final name   = a['Name']        as String? ?? '';
        final artist = a['AlbumArtist'] as String? ?? '';
        if (aid.isEmpty || usedIds.contains(aid)) continue;
        final tag    = (a['ImageTags'] as Map?)?.cast<String, dynamic>()['Primary'] as String?;
        final artUrl = JellyfinApi.imageUrl(aid, size: 300, tag: tag);
        entries.add(_DeckEntry(
          albumId:    aid,
          albumTitle: name,
          artist:     artist,
          artUrl:     artUrl,
          progress:   null,
          session:    null,
        ));
      }
    }

    setState(() {
      _topSession  = topSession;
      _deckEntries = entries;
    });
  }

  Future<void> _patchStaleTitles(List<String> albumIds) async {
    var changed = false;
    for (final id in albumIds) {
      try {
        final item  = await JellyfinApi.getItem(id);
        final title = item['Name'] as String? ?? '';
        if (title.isNotEmpty) {
          await OnDeckService.patchAlbumTitle(id, title);
          changed = true;
        }
      } catch (_) {}
    }
    if (changed && mounted) _loadDeckData();
  }

  // ── Library data ──────────────────────────────────────────────────────────────

  Future<void> _loadData({bool refreshMixes = false}) async {
    if (refreshMixes) {
      await PresetMixService.invalidate();
      ref.invalidate(presetMixesProvider);
    }
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        JellyfinApi.getRecentAlbums(limit: 27),
        JellyfinApi.getArtists(),
        JellyfinApi.getAIArtists(),
      ]);
      if (!mounted) return;

      final seen = <String>{};
      final artists = [
        ...(results[1]['Items'] as List? ?? []).cast<Map<String, dynamic>>(),
        ...(results[2]['Items'] as List? ?? []).cast<Map<String, dynamic>>(),
      ].where((a) {
            final name = (a['Name'] as String? ?? '').trim();
            if (name.isEmpty || name.contains(',')) return false;
            return seen.add(name.toLowerCase());
          })
          .toList();

      // Artist Corner rotates once per day — consistent order all day.
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final prefs = await Hive.openBox<dynamic>('vibe_prefs');
      int seed;
      if (prefs.get('artist_corner_date') == today) {
        seed = (prefs.get('artist_corner_seed') as int?) ?? DateTime.now().millisecondsSinceEpoch;
      } else {
        seed = DateTime.now().millisecondsSinceEpoch;
        await prefs.put('artist_corner_date', today);
        await prefs.put('artist_corner_seed', seed);
      }
      artists.shuffle(Random(seed));

      // Fetch the daily artist's albums — sequential after shuffle so we know
      // which artist is featured today.
      List<Map<String, dynamic>> dailyAlbums = [];
      if (artists.isNotEmpty) {
        final artistId = artists.first['Id'] as String? ?? '';
        if (artistId.isNotEmpty) {
          try {
            final res = await JellyfinApi.getArtistAlbums(artistId);
            dailyAlbums = ((res['Items'] as List?) ?? [])
                .cast<Map<String, dynamic>>();
          } catch (_) {}
        }
      }

      setState(() {
        _recentAlbums      = (results[0]['Items'] as List? ?? []).cast();
        _artists           = artists;
        _dailyArtistAlbums = dailyAlbums;
        _loading           = false;
      });
      _loadDeckData(); // re-run now that _recentAlbums is populated
      _enterCtrl.forward(from: 0);
    } on JellyfinAuthException {
      if (!mounted) return;
      setState(() => _loading = false);
      final reconnected = await ReauthSheet.show(context);
      if (reconnected && mounted) _loadData();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────────

  Future<void> _resumeSession(AlbumSession session) async {
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
      debugPrint('resumeSession error: $e');
    }
  }

  void _playDeckEntry(_DeckEntry entry) {
    // Always go to the album page — Resume is shown there alongside
    // the track list so the user can choose to resume or pick a specific song.
    context.push(
      '/album/${entry.albumId}'
      '?name=${Uri.encodeComponent(entry.albumTitle)}'
      '&artist=${Uri.encodeComponent(entry.artist)}',
    );
  }

  void _openFireMix() {
    final tracks = ref.read(fireMixProvider).toList();
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fire tracks yet — mark songs while listening!'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MixDetailScreen(
          name:   'Fire Mix',
          tracks: [...tracks]..shuffle(),
        ),
      ),
    );
  }

  void _openPresetMix(VibeMix mix) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MixDetailScreen(
          name:   mix.name,
          tracks: mix.tracks,
          mixId:  mix.id,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final ambient = ref.watch(ambientThemeProvider);

    return Stack(
      children: [
        // Breathing glow
        Positioned(
          top: 0, left: 0, right: 0,
          child: VibeBreathingGlow(
            color:          ambient.playButtonColor,
            colorBright:    ambient.waveformActive,
            heightFraction: 0.60,
          ),
        ),

        if (_loading)
          const Positioned.fill(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Positioned.fill(child: _ErrorState(error: _error!, theme: theme, onRetry: _loadData))
        else
          RefreshIndicator(
            onRefresh: () => _loadData(refreshMixes: true),
            child: ListView(
              padding: EdgeInsets.only(
                top:    8,
                bottom: MediaQuery.of(context).padding.bottom + 100,
              ),
              children: [

                // ── Jump Back In ──────────────────────────────────────────────
                if (_topSession != null) ...[
                  const SizedBox(height: 16),
                  VibeFadeSlide(
                    animation: _sec(0),
                    child: _JumpBackInHero(
                      session:  _topSession!,
                      theme:    theme,
                      onResume: () => _resumeSession(_topSession!),
                    ),
                  ),
                ],

                // ── On Deck ───────────────────────────────────────────────────
                if (_deckEntries.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(
                    animation: _sec(1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'On Deck',
                            style: TextStyle(
                              color:       theme.textColor,
                              fontSize:    18,
                              fontWeight:  FontWeight.w700,
                              letterSpacing: 0.4,
                              shadows: [
                                Shadow(color: theme.accent.withAlpha(0xCC), blurRadius: 10),
                                Shadow(color: theme.accentBright.withAlpha(0x66), blurRadius: 24),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push('/on-deck'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'See All',
                                  style: TextStyle(
                                    color:      theme.accentBright,
                                    fontSize:   13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.chevron_right_rounded,
                                    color: theme.accentBright, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  VibeFadeSlide(
                    animation: _sec(1),
                    child: _OnDeckGrid(
                      entries:       _deckEntries,
                      theme:         theme,
                      pageCtrl:      _deckPageCtrl,
                      page:          _deckPage,
                      onPageChanged: (p) => setState(() => _deckPage = p),
                      onTap:         _playDeckEntry,
                    ),
                  ),
                ],

                // ── ViBE Out ──────────────────────────────────────────────────
                VibeFadeSlide(
                  animation: _sec(2),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: VibeOutSection(theme: theme),
                  ),
                ),

                // ── Recently Added in ViBE ────────────────────────────────────
                if (_recentAlbums.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(animation: _sec(3),
                    child: VibeSectionHeader(title: 'Recently Added in ViBE', theme: theme)),
                  const SizedBox(height: 14),
                  VibeFadeSlide(animation: _sec(3),
                    child: SizedBox(
                      height: _kAlbumSize + 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding:        const EdgeInsets.symmetric(horizontal: 20),
                        itemCount:      _recentAlbums.take(10).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) {
                          final a      = _recentAlbums[i];
                          final id     = a['Id']             as String? ?? '';
                          final name   = a['Name']           as String? ?? '';
                          final artist = a['AlbumArtist']    as String? ?? '';
                          final year   = a['ProductionYear'] as int?;
                          final yParam = year != null ? '&year=$year' : '';
                          return VibeAlbumCard(
                            item: a, theme: theme,
                            onPress: () => context.push(
                              '/album/$id?name=${Uri.encodeComponent(name)}&artist=${Uri.encodeComponent(artist)}$yParam',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // ── Fire Mix ──────────────────────────────────────────────────
                const SizedBox(height: 28),
                VibeFadeSlide(
                  animation: _sec(4),
                  child: _FireMixCard(theme: theme, onTap: _openFireMix),
                ),

                // ── Mixed For You ─────────────────────────────────────────────
                const SizedBox(height: 28),
                VibeFadeSlide(animation: _sec(5),
                  child: VibeSectionHeader(title: 'Mixed For You', theme: theme)),
                const SizedBox(height: 14),
                VibeFadeSlide(animation: _sec(5),
                  child: _MixedForYouRow(
                    theme:  theme,
                    onOpen: _openPresetMix,
                  ),
                ),

                // ── Daily Artist ──────────────────────────────────────────────
                if (_artists.isNotEmpty && _dailyArtistAlbums.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(
                    animation: _sec(6),
                    child: _DailyArtistSection(
                      artist:      _artists.first,
                      albums:      _dailyArtistAlbums,
                      theme:       theme,
                      onSeeAll:    () => context.push('/all-artists'),
                      onArtistTap: () {
                        final a = _artists.first;
                        context.push(
                          '/artist/${a['Id']}'
                          '?name=${Uri.encodeComponent(a['Name'] as String? ?? '')}',
                        );
                      },
                      onAlbumTap: (a) {
                        final id     = a['Id']             as String? ?? '';
                        final name   = a['Name']           as String? ?? '';
                        final artist = a['AlbumArtist']    as String? ?? '';
                        final year   = a['ProductionYear'] as int?;
                        final yParam = year != null ? '&year=$year' : '';
                        context.push(
                          '/album/$id'
                          '?name=${Uri.encodeComponent(name)}'
                          '&artist=${Uri.encodeComponent(artist)}'
                          '$yParam',
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 28),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Jump Back In hero ─────────────────────────────────────────────────────────

class _JumpBackInHero extends StatelessWidget {
  final AlbumSession session;
  final VibeTheme    theme;
  final VoidCallback onResume;

  const _JumpBackInHero({
    required this.session,
    required this.theme,
    required this.onResume,
  });

  String _progressLabel() {
    final trackNum = session.trackNumber ?? (session.queueIndex + 1);
    final dur = Duration(milliseconds: session.trackDurationMs);
    final pos = Duration(milliseconds: session.trackPositionMs);
    if (dur.inSeconds > 0) {
      final left = dur - pos;
      if (left.inSeconds > 0) {
        final m = left.inMinutes;
        final s = left.inSeconds % 60;
        return 'Track $trackNum • $m:${s.toString().padLeft(2, '0')} left';
      }
    }
    return 'Track $trackNum';
  }

  @override
  Widget build(BuildContext context) {
    final accent   = theme.accent;
    final artUrl   = session.artUrl;
    final progress = session.progressFraction; // album-level progress

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          // Blurred artwork background
          if (artUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: CachedNetworkImage(
                  imageUrl:     artUrl,
                  fit:          BoxFit.cover,
                  errorWidget:  (_, _, _) => const SizedBox(),
                ),
              ),
            ),
          // Dark overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.topCenter,
                  end:    Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(0xBB),
                    Colors.black.withAlpha(0xDD),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label
                Row(
                  children: [
                    Icon(Icons.history_rounded, size: 13, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'JUMP BACK IN',
                      style: TextStyle(
                        color:         accent,
                        fontSize:      11,
                        fontWeight:    FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Artwork + info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Album art
                    if (artUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl:    artUrl,
                          width:       72,
                          height:      72,
                          fit:         BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color:        theme.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.album, color: theme.textFaint, size: 32),
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.trackTitle,
                            style: const TextStyle(
                              color:      Colors.white,
                              fontSize:   16,
                              fontWeight: FontWeight.w700,
                              height:     1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            session.artist,
                            style: TextStyle(
                              color:    Colors.white.withAlpha(0xAA),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (session.albumTitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              session.albumTitle,
                              style: TextStyle(
                                color:    Colors.white.withAlpha(0x66),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            _progressLabel(),
                            style: TextStyle(
                              color:    Colors.white.withAlpha(0x88),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Album progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value:           progress,
                    minHeight:       3,
                    backgroundColor: Colors.white.withAlpha(0x22),
                    valueColor:      AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 14),
                // Resume button
                GestureDetector(
                  onTap: onResume,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color:        accent.withAlpha(0xEE),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: accent.withAlpha(0x55), blurRadius: 12),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Resume',
                          style: TextStyle(
                            color:      Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize:   13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── On Deck paginated grid ────────────────────────────────────────────────────

class _OnDeckGrid extends StatelessWidget {
  final List<_DeckEntry>         entries;
  final VibeTheme                theme;
  final PageController           pageCtrl;
  final int                      page;
  final ValueChanged<int>        onPageChanged;
  final ValueChanged<_DeckEntry> onTap;

  const _OnDeckGrid({
    required this.entries,
    required this.theme,
    required this.pageCtrl,
    required this.page,
    required this.onPageChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w     = MediaQuery.of(context).size.width;
    // 20px side padding × 2 = 40, two 8px column gaps = 16 → total 56
    final cardW = (w - 56) / 3;
    final itemH = cardW + 46; // square art + 46px for two lines of text
    final gridH = itemH * 3 + 8 * 2; // 3 rows + 2 row-gaps
    // Always 3 pages so dots and swiping are always available.
    const kPageCount = 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: gridH,
          child: PageView.builder(
            controller:    pageCtrl,
            onPageChanged: onPageChanged,
            itemCount:     kPageCount,
            itemBuilder:   (_, pageIdx) {
              final start = pageIdx * 9;
              final slice = start < entries.length
                  ? entries.sublist(start, min(start + 9, entries.length))
                  : <_DeckEntry>[];
              // Empty page — still swipeable, just shows nothing.
              if (slice.isEmpty) return const SizedBox.expand();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing:  8,
                    childAspectRatio: cardW / itemH,
                  ),
                  itemCount: slice.length,
                  itemBuilder: (_, i) => _DeckCard(
                    entry: slice[i],
                    theme: theme,
                    onTap: () => onTap(slice[i]),
                  ),
                ),
              );
            },
          ),
        ),
        // 3 dots — always visible, active dot is wider and accent-coloured.
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            kPageCount,
            (i) => AnimatedContainer(
              duration:  const Duration(milliseconds: 200),
              margin:    const EdgeInsets.symmetric(horizontal: 3),
              width:     i == page ? 16 : 6,
              height:    6,
              decoration: BoxDecoration(
                color:        i == page
                    ? theme.accent
                    : Colors.white.withAlpha(0x44),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Individual deck card ──────────────────────────────────────────────────────

class _DeckCard extends StatelessWidget {
  final _DeckEntry   entry;
  final VibeTheme    theme;
  final VoidCallback onTap;

  const _DeckCard({
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
                // Album artwork
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
                // Thin progress bar at the bottom of the art — only for in-progress albums.
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

// ── Fire Mix premium card ─────────────────────────────────────────────────────

class _FireMixCard extends ConsumerWidget {
  final VibeTheme    theme;
  final VoidCallback onTap;
  const _FireMixCard({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks     = ref.watch(fireMixProvider);
    final collageUrls = tracks
        .map((t) => t.artworkUrl)
        .toSet()
        .take(4)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: VibeBounce(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 130,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Art collage background (blurred + desaturated via ColorFilter)
                if (collageUrls.length >= 4)
                  ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      0.3, 0.6, 0.1, 0, 0,
                      0.3, 0.6, 0.1, 0, 0,
                      0.3, 0.6, 0.1, 0, 0,
                      0,   0,   0,   1, 0,
                    ]),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: ArtCollage(imageUrls: collageUrls, theme: theme),
                    ),
                  )
                else
                  Container(color: const Color(0xFF1A0A00)),

                // Orange gradient overlay
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end:   Alignment.centerRight,
                      colors: [
                        const Color(0xFFFF4500).withAlpha(0xEE),
                        const Color(0xFFFF8C00).withAlpha(0xCC),
                        const Color(0xFFFF4500).withAlpha(0x88),
                      ],
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.whatshot_rounded,
                          color: Colors.white, size: 44),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment:  MainAxisAlignment.center,
                          children: [
                            const Text(
                              'FIRE MIX',
                              style: TextStyle(
                                color:         Colors.white,
                                fontSize:      11,
                                fontWeight:    FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tracks.isEmpty
                                  ? 'Mark songs as 🔥 to fill this'
                                  : '${tracks.length} banger${tracks.length == 1 ? '' : 's'} · All yours',
                              style: TextStyle(
                                color:    Colors.white.withAlpha(0xCC),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:  Colors.white.withAlpha(0x22),
                          shape:  BoxShape.circle,
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mixed For You horizontal row ──────────────────────────────────────────────

class _MixedForYouRow extends ConsumerWidget {
  final VibeTheme              theme;
  final void Function(VibeMix) onOpen;
  const _MixedForYouRow({required this.theme, required this.onOpen});

  static const _kCardW = 148.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMixes = ref.watch(presetMixesProvider);
    return asyncMixes.when(
      loading: () => SizedBox(
        height: _kCardW + 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding:         const EdgeInsets.symmetric(horizontal: 20),
          itemCount:       4,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => _shimmer(_kCardW),
        ),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Could not generate mixes',
            style: TextStyle(color: theme.textFaint, fontSize: 13)),
      ),
      data: (mixes) {
        if (mixes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Add more albums to unlock personalised mixes',
              style: TextStyle(color: theme.textFaint, fontSize: 13),
            ),
          );
        }
        return SizedBox(
          height: _kCardW + 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:         const EdgeInsets.symmetric(horizontal: 20),
            itemCount:       mixes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _VibeMixCard(
              mix:   mixes[i],
              theme: theme,
              size:  _kCardW,
              onTap: () => onOpen(mixes[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _shimmer(double size) => Container(
    width:  size,
    height: size,
    decoration: BoxDecoration(
      color:        theme.surface,
      borderRadius: BorderRadius.circular(12),
    ),
  );
}

// ── Single preset mix card ────────────────────────────────────────────────────

class _VibeMixCard extends StatelessWidget {
  final VibeMix    mix;
  final VibeTheme  theme;
  final double     size;
  final VoidCallback onTap;

  const _VibeMixCard({
    required this.mix,
    required this.theme,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final collage = mix.tracks
        .map((t) => t.artworkUrl)
        .toSet()
        .take(4)
        .toList();

    return VibeBounce(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2×2 collage with subtle glow
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:      theme.accent.withAlpha(0x44),
                    blurRadius: 14,
                    offset:     const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width:  size,
                  height: size,
                  child: ArtCollage(imageUrls: collage, theme: theme),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mix.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:      theme.textColor,
                fontSize:   13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${mix.tracks.length} tracks',
              style: TextStyle(
                color:    theme.textFaint,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Daily Artist section ──────────────────────────────────────────────────────

class _DailyArtistSection extends StatelessWidget {
  final Map<String, dynamic>            artist;
  final List<Map<String, dynamic>>      albums;
  final VibeTheme                       theme;
  final VoidCallback                    onSeeAll;
  final VoidCallback                    onArtistTap;
  final void Function(Map<String, dynamic>) onAlbumTap;

  const _DailyArtistSection({
    required this.artist,
    required this.albums,
    required this.theme,
    required this.onSeeAll,
    required this.onArtistTap,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    final id   = artist['Id']   as String? ?? '';
    final name = artist['Name'] as String? ?? '';
    final tag  = (artist['ImageTags'] as Map?)
        ?.cast<String, dynamic>()['Primary'] as String?;
    final imgUrl = id.isNotEmpty
        ? JellyfinApi.imageUrl(id, type: 'Primary', size: 200, tag: tag)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow
              Text(
                "TODAY'S ARTIST",
                style: TextStyle(
                  color:         theme.accent,
                  fontSize:      11,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              // Artist row: avatar + name + See All
              Row(
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: onArtistTap,
                    child: ClipOval(
                      child: imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl:    imgUrl,
                              width:       48,
                              height:      48,
                              fit:         BoxFit.cover,
                              errorWidget: (_, _, _) => _avatarFallback(),
                            )
                          : _avatarFallback(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + chevron — tappable to artist page
                  Expanded(
                    child: GestureDetector(
                      onTap: onArtistTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:         theme.textColor,
                                fontSize:      18,
                                fontWeight:    FontWeight.w700,
                                letterSpacing: 0.3,
                                shadows: [
                                  Shadow(color: theme.accent.withAlpha(0xCC), blurRadius: 10),
                                  Shadow(color: theme.accentBright.withAlpha(0x55), blurRadius: 22),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: theme.accentBright, size: 20),
                        ],
                      ),
                    ),
                  ),
                  // All Artists → /all-artists
                  GestureDetector(
                    onTap: onSeeAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'All Artists',
                          style: TextStyle(
                            color:      theme.accentBright,
                            fontSize:   13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            color: theme.accentBright, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Albums row
        SizedBox(
          height: _kAlbumSize + 72,
          child: ListView.separated(
            scrollDirection:  Axis.horizontal,
            padding:          const EdgeInsets.symmetric(horizontal: 20),
            itemCount:        albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) => VibeAlbumCard(
              item:    albums[i],
              theme:   theme,
              onPress: () => onAlbumTap(albums[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _avatarFallback() => Container(
    width:  48,
    height: 48,
    decoration: BoxDecoration(
      color:  theme.surface,
      shape:  BoxShape.circle,
    ),
    child: Icon(Icons.person_rounded, color: theme.textFaint, size: 24),
  );
}

// ── Error state ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String     error;
  final VibeTheme  theme;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.theme, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: theme.textFaint),
          const SizedBox(height: 16),
          Text('Could not reach Jellyfin',
              style: TextStyle(color: theme.textColor, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textFaint, fontSize: 11)),
          const SizedBox(height: 24),
          VibeBounce(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color:        theme.accent,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: theme.accent.withAlpha(0x66), blurRadius: 14),
                ],
              ),
              child: Text('Retry',
                  style: TextStyle(color: theme.textColor, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );
}
