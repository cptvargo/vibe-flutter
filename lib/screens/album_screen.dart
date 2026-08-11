import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../theme/palette_service.dart';
import '../theme/vibe_theme.dart';
import '../widgets/mini_player.dart';

class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String albumName;
  final String artistName;
  final int?   year;

  const AlbumScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    required this.artistName,
    this.year,
  });

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  List<VibeTrack>              _tracks         = [];
  bool                         _loading        = true;
  VibeTheme?                   _albumTheme;
  String?                      _artistId;
  List<Map<String, dynamic>>   _similarArtists = [];

  @override
  void initState() {
    super.initState();
    _loadTracks();
    _extractPalette();
  }

  Future<void> _extractPalette() async {
    try {
      final url     = JellyfinApi.colorExtractionUrl(widget.albumId);
      final palette = await PaletteService.extractFromUrl(url, widget.albumId);
      if (palette != null && mounted) {
        setState(() => _albumTheme = VibeTheme.from(palette));
      }
    } catch (_) {}
  }

  Future<void> _loadTracks() async {
    try {
      final isAI   = ref.read(isAIProvider);
      final result = await JellyfinApi.getAlbumTracks(widget.albumId);
      final items  = ((result['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        final tracks = items.map((j) => VibeTrack.fromJellyfin(j, isAI: isAI)).toList();
        setState(() {
          _tracks  = tracks;
          _loading = false;
        });
        if (tracks.isNotEmpty) {
          _artistId = tracks.first.artistId;
          _loadSimilarArtists();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSimilarArtists() async {
    final id = _artistId;
    if (id == null || id.isEmpty) return;
    final results = await JellyfinApi.getSimilarArtistsByGenre(
      id,
      albumId:    widget.albumId,
      artistName: widget.artistName,
      limit: 8,
    );
    if (mounted && results.isNotEmpty) {
      setState(() => _similarArtists = results);
    }
  }

  Future<void> _play(int index) async {
    if (_tracks.isEmpty || !mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(
      _tracks,
      startIndex: index.clamp(0, _tracks.length - 1),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final VibeTheme theme = _albumTheme ?? ref.watch(themeProvider);
    final screenW = MediaQuery.of(context).size.width;
    final artUrl  = JellyfinApi.imageUrl(widget.albumId, size: 600);

    // 16px margin each side — art feels wide but page never feels cramped
    const hPad   = 16.0;
    final artSize = screenW - hPad * 2;

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          // ── Scrollable content ───────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [

                // ── Art + header ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Room for the floating nav buttons
                      const SizedBox(height: 60),

                      // Album artwork — square card, centered, with glow shadow
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: hPad),
                        child: Container(
                          width: artSize,
                          height: artSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent.withAlpha(0x55),
                                blurRadius: 40,
                                spreadRadius: 2,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black.withAlpha(0x77),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                              imageUrl: artUrl,
                              width: artSize,
                              height: artSize,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  Container(color: theme.surface),
                              errorWidget: (_, _, _) =>
                                  Container(color: theme.surface),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Album title + play button — aligned with art edges
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: hPad),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.albumName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.1,
                                      shadows: [
                                        Shadow(
                                          color: theme.accent,
                                          blurRadius: 14,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      widget.artistName,
                                      if (widget.year != null) '${widget.year}',
                                      if (_tracks.isNotEmpty)
                                        '${_tracks.length} '
                                        '${_tracks.length == 1 ? 'track' : 'tracks'}',
                                    ].join('  ·  '),
                                    style: TextStyle(
                                      color: theme.accentBright,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Play all
                            GestureDetector(
                              onTap: () => _play(0),
                              child: Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  color: theme.accent,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.accent.withAlpha(0xAA),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Thin divider between header and track list
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: hPad),
                        child: Divider(
                          color: Colors.white.withAlpha(0x18),
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Track list ─────────────────────────────────────────────
                if (_loading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  StreamBuilder<MediaItem?>(
                    stream: ref.read(audioHandlerProvider).mediaItem,
                    builder: (context, snap) {
                      final currentId = snap.data?.id;
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final track     = _tracks[i];
                            final isCurrent = track.id == currentId;
                            return GestureDetector(
                              onTap: () => _play(i),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    hPad, 0, hPad, 0),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  child: Row(
                                    children: [
                                      // Track number or now-playing equalizer
                                      SizedBox(
                                        width: 24,
                                        child: isCurrent
                                            ? Center(
                                                child: _NowPlayingBars(
                                                  color: theme.accent,
                                                ),
                                              )
                                            : Text(
                                                '${i + 1}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color: theme.textFaint,
                                                    fontSize: 13),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Title + featured artist
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrent
                                                    ? theme.accentBright
                                                    : theme.textColor,
                                                fontSize: 14,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                            if (track.artist.isNotEmpty &&
                                                track.artist != widget.artistName)
                                              Text(
                                                track.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: theme.textDim,
                                                    fontSize: 12),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Duration
                                      Text(
                                        _fmt(track.duration),
                                        style: TextStyle(
                                            color: theme.textFaint, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: _tracks.length,
                        ),
                      );
                    },
                  ),
                  // ── You might also like ──────────────────────────────────
                  if (_similarArtists.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _YouMightAlsoLike(
                        artists: _similarArtists,
                        theme:   theme,
                      ),
                    ),

                  const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                ],
              ],
            ),
          ), // SafeArea

          // ── Floating nav buttons ─────────────────────────────────────────
          // Separate SafeArea overlay so they sit above the scroll content
          // without pushing the art down or creating dead space.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _NavButton(
                    icon: Icons.arrow_back_ios_new,
                    size: 18,
                    onTap: () => context.pop(),
                  ),
                  const Spacer(),
                  _NavButton(
                    icon: Icons.home_rounded,
                    size: 20,
                    onTap: () => context.go('/'),
                  ),
                ],
              ),
            ),
          ),

          // MiniPlayer
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

class _YouMightAlsoLike extends StatelessWidget {
  final List<Map<String, dynamic>> artists;
  final VibeTheme                  theme;

  const _YouMightAlsoLike({required this.artists, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.white.withAlpha(0x18), height: 1),
          const SizedBox(height: 20),
          Text(
            'You might also like',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final a      = artists[i];
                final id     = a['Id']   as String? ?? '';
                final name   = a['Name'] as String? ?? '';
                final artUrl = JellyfinApi.imageUrl(id, size: 200);
                return GestureDetector(
                  onTap: () => context.push(
                    '/artist/$id?name=${Uri.encodeComponent(name)}',
                  ),
                  child: SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.surface,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(0x44),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: artUrl,
                              width: 72, height: 72,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: theme.surface),
                              errorWidget: (_, _, _) => Icon(
                                Icons.person_rounded,
                                color: theme.textFaint,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Three animated bars — now-playing indicator in the track list
class _NowPlayingBars extends StatefulWidget {
  final Color color;
  const _NowPlayingBars({required this.color});
  @override
  State<_NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<_NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _bar(double h) => Container(
    width: 3, height: h,
    decoration: BoxDecoration(
      color: widget.color,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t  = _ctrl.value * 2 * pi;
        final h1 = 3 + 11 * ((sin(t * 1.10)       + 1) / 2);
        final h2 = 3 + 11 * ((sin(t * 0.85 + 1.0) + 1) / 2);
        final h3 = 3 + 11 * ((sin(t * 1.30 + 2.1) + 1) / 2);
        return SizedBox(
          width: 16, height: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [_bar(h1), _bar(h2), _bar(h3)],
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final double   size;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withAlpha(0x66),
      ),
      child: Icon(icon, color: Colors.white, size: size),
    ),
  );
}
