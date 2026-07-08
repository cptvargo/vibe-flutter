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
  List<VibeTrack> _tracks     = [];
  bool            _loading    = true;
  VibeTheme?      _albumTheme;

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
        setState(() {
          _tracks  = items.map((j) => VibeTrack.fromJellyfin(j, isAI: isAI)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final track = _tracks[i];
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
                                  // Track number
                                  SizedBox(
                                    width: 24,
                                    child: Text(
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
                                            color: theme.textColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
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
