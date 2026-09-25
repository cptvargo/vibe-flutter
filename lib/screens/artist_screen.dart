import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../theme/palette_service.dart';
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
                      // Hero image — full bleed from screen top
                      _ArtistHero(
                        artistId:   widget.artistId,
                        artistName: widget.artistName,
                      ),

                      const SizedBox(height: 16),

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
                            albumId:    albumId,
                            name:       name,
                            year:       year,
                            artistName: widget.artistName,
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

// ── Hero image widget ─────────────────────────────────────────────────────────

class _ArtistHero extends StatelessWidget {
  final String artistId;
  final String artistName;

  const _ArtistHero({required this.artistId, required this.artistName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: JellyfinApi.imageUrl(artistId, size: 800),
            fit: BoxFit.cover,
            placeholder: (_, _) => const ColoredBox(color: Color(0xFF0D0D1A)),
            errorWidget: (_, _, _) => ColoredBox(
              color: const Color(0xFF0D0D1A),
              child: Center(
                child: Text(
                  artistName.isNotEmpty ? artistName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0x44FFFFFF),
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          // Status bar darkening gradient
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withAlpha(0x77), Colors.transparent],
                stops: const [0.0, 0.35],
              ),
            ),
          ),
          // Bottom fade into page background
          const Positioned(
            bottom: 0, left: 0, right: 0,
            child: SizedBox(
              height: 110,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xFF06060F)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Album row ─────────────────────────────────────────────────────────────────

class _AlbumRow extends StatelessWidget {
  final String artUrl;
  final String albumId;
  final String name;
  final String artistName;
  final int? year;
  final VibePalette palette;
  final bool isLast;
  final VoidCallback onTap;

  const _AlbumRow({
    required this.artUrl,
    required this.albumId,
    required this.name,
    required this.artistName,
    required this.year,
    required this.palette,
    required this.isLast,
    required this.onTap,
  });

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextSheet(
        artUrl: artUrl,
        title:  name,
        subtitle: year != null ? '$year' : artistName,
        items: [
          _SheetItem(
            icon:  Icons.play_arrow_rounded,
            label: 'Play Album',
            onTap: () { Navigator.pop(context); onTap(); },
          ),
        ],
      ),
    );
  }

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
                  bottom: BorderSide(color: Colors.white.withAlpha(0x0D)),
                ),
              ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedNetworkImage(
                imageUrl: artUrl,
                width: 58, height: 58,
                fit: BoxFit.cover,
                placeholder:  (_, _) => Container(width: 58, height: 58, color: Colors.white.withAlpha(0x0D)),
                errorWidget:  (_, _, _) => Container(width: 58, height: 58, color: Colors.white.withAlpha(0x0A)),
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
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showMenu(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 4, 12),
                child: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withAlpha(0x44),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared bottom-sheet context menu ─────────────────────────────────────────

class _SheetItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetItem({required this.icon, required this.label, required this.onTap});
}

class _ContextSheet extends StatelessWidget {
  final String artUrl;
  final String title;
  final String subtitle;
  final List<_SheetItem> items;

  const _ContextSheet({
    required this.artUrl,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(0x30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: artUrl,
                    width: 48, height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        Container(width: 48, height: 48, color: const Color(0xFF2A2A40)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(0x88), fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withAlpha(0x15), height: 1),
          const SizedBox(height: 4),
          for (final item in items)
            InkWell(
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  children: [
                    Icon(item.icon, color: Colors.white.withAlpha(0xBB), size: 22),
                    const SizedBox(width: 16),
                    Text(item.label,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
