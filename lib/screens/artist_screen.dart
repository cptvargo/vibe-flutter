import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../theme/palette_service.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/mini_player.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  final String artistId;
  final String artistName;

  const ArtistScreen({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  List<Map<String, dynamic>> _albums = [];
  bool _loadingPlay = false;
  VibePalette? _palette;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      JellyfinApi.getArtistAlbums(widget.artistId).then((r) {
        if (mounted) {
          setState(() => _albums =
              ((r['Items'] as List?) ?? []).cast<Map<String, dynamic>>());
        }
      }).catchError((_) {}),
      PaletteService.extractFromUrl(
        JellyfinApi.colorExtractionUrl(widget.artistId),
        widget.artistId,
      ).then((p) {
        if (p != null && mounted) setState(() => _palette = p);
      }),
    ]);
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_loadingPlay || !mounted) return;
    final isAI = ref.read(isAIProvider);
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    setState(() => _loadingPlay = true);
    try {
      final res = await JellyfinApi.getArtistAllTracks(widget.artistId);
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (items.isEmpty) return;
      final tracks = items.map((j) => VibeTrack.fromJellyfin(j, isAI: isAI)).toList();
      if (shuffle) tracks.shuffle();
      ref.read(audioHandlerProvider).playTracks(tracks, startIndex: 0, playbackContext: 'shuffle');
    } catch (e) {
      debugPrint('ArtistScreen._playAll error: $e');
    } finally {
      if (mounted) setState(() => _loadingPlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final palette = _palette ?? VibePalette.fallback;

    // Gradient: artist palette color bleeds from top, fades to near-black by 70%
    final gradTop = Color.lerp(palette.darkMuted, const Color(0xFF06060F), 0.15)!;
    final gradMid = Color.lerp(palette.darkVibrant, const Color(0xFF06060F), 0.4)!;

    return Scaffold(
      backgroundColor: const Color(0xFF06060F),
      body: Stack(
        children: [
          // ── Full-screen gradient pulled from artist palette ──────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [gradTop, gradMid, const Color(0xFF06060F)],
                  stops: const [0.0, 0.4, 0.72],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                // ── Hero ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 60),

                      // Large centered circle avatar with palette glow
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: palette.vibrant.withAlpha(0x55),
                              blurRadius: 48,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: ArtistAvatar(
                          id: widget.artistId,
                          name: widget.artistName,
                          size: 168,
                          theme: theme,
                          circle: true,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Artist name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          widget.artistName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            shadows: [
                              Shadow(
                                color: palette.vibrant.withAlpha(0x99),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_albums.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${_albums.length} album${_albums.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.white.withAlpha(0x55),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Play All (full-width) + Shuffle (icon button)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _playAll,
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: palette.vibrant,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.vibrant.withAlpha(0x55),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_loadingPlay)
                                        const SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      else
                                        const Icon(Icons.play_arrow_rounded,
                                            color: Colors.white, size: 24),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Play All',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _playAll(shuffle: true),
                              child: Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(0x14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(0x20),
                                  ),
                                ),
                                child: Icon(
                                  Icons.shuffle_rounded,
                                  color: Colors.white.withAlpha(0xBB),
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 36),
                    ],
                  ),
                ),

                // ── Discography label ─────────────────────────────────────
                if (_albums.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'DISCOGRAPHY',
                        style: TextStyle(
                          color: Colors.white.withAlpha(0x44),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                  ),

                // ── Album list rows ───────────────────────────────────────
                if (_albums.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: 20, right: 20,
                      bottom: MediaQuery.of(context).padding.bottom + 100,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final album   = _albums[i];
                          final albumId = album['Id'] as String? ?? '';
                          final tag     = (album['ImageTags'] as Map?)?['Primary'] as String?;
                          final artUrl  = JellyfinApi.imageUrl(albumId, size: 200, tag: tag);
                          final name    = album['Name'] as String? ?? '';
                          final year    = album['ProductionYear'] as int?;
                          return _AlbumRow(
                            artUrl:     artUrl,
                            name:       name,
                            year:       year,
                            palette:    palette,
                            isLast:     i == _albums.length - 1,
                            onTap: () {
                              final nameEnc   = Uri.encodeComponent(name);
                              final artistEnc = Uri.encodeComponent(widget.artistName);
                              final yearParam = year != null ? '&year=$year' : '';
                              context.push(
                                '/album/$albumId?name=$nameEnc&artist=$artistEnc$yearParam',
                              );
                            },
                          );
                        },
                        childCount: _albums.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Back button ───────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withAlpha(0x55),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ),

          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  final String artUrl;
  final String name;
  final int? year;
  final VibePalette palette;
  final bool isLast;
  final VoidCallback onTap;

  const _AlbumRow({
    required this.artUrl,
    required this.name,
    required this.year,
    required this.palette,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: isLast
            ? null
            : BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withAlpha(0x0D),
                  ),
                ),
              ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedNetworkImage(
                imageUrl: artUrl,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: 58, height: 58,
                  color: Colors.white.withAlpha(0x0D),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 58, height: 58,
                  color: Colors.white.withAlpha(0x0A),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (year != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '$year',
                      style: TextStyle(
                        color: Colors.white.withAlpha(0x44),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withAlpha(0x2E),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
