import 'dart:math' as math;
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
      final items  = ((result['Items'] as List?) ?? [])
          .cast<Map<String, dynamic>>();
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
    context.push('/player'); // open instantly
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
    final topPad  = MediaQuery.of(context).padding.top;
    final artUrl  = JellyfinApi.imageUrl(widget.albumId, size: 600);
    // Cap art at 460px so the hero doesn't overflow on wide desktop windows
    final artSize = math.min(screenW, 460.0);
    final heroH   = artSize + 80.0;

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [

              // ── Hero ──────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SizedBox(
                  height: heroH, // artSize + 80 (capped so tracks are visible on desktop)
                  child: Stack(
                    children: [
                      // Album art — square fill
                      Positioned(
                        top: 0, left: 0, right: 0,
                        height: artSize,
                        child: CachedNetworkImage(
                          imageUrl: artUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: theme.surface),
                          errorWidget: (_, _, _) =>
                              Container(color: theme.surface),
                        ),
                      ),

                      // Gradient: art → theme.background
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.accent.withAlpha(0x44),
                                Colors.black.withAlpha(0x77),
                                theme.background,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Back button
                      Positioned(
                        top: topPad + 12, left: 16,
                        child: GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withAlpha(0x66),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),

                      // Album info + play button
                      Positioned(
                        left: 20, right: 20, bottom: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.albumName,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                      shadows: [
                                        Shadow(color: theme.accent,
                                            blurRadius: 12),
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
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            // Play all button
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
                                      blurRadius: 20, spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 30),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Track list ─────────────────────────────────────────────────
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _tracks.length == 1 ? 'Single' : 'Tracks',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final track = _tracks[i];
                      return GestureDetector(
                        onTap: () => _play(i),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            children: [
                              // Track number
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${i + 1}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: theme.textFaint, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title + artist
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      );
                    },
                    childCount: _tracks.length,
                  ),
                ),
                // Bottom padding so content clears the MiniPlayer
                const SliverPadding(
                    padding: EdgeInsets.only(bottom: 100)),
              ],
            ],
          ),

          // MiniPlayer — floats above content (outside MainShell on this route)
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}
