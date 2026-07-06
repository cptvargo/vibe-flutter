import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
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

  @override
  void initState() {
    super.initState();
    JellyfinApi.getArtistAlbums(widget.artistId)
        .then((r) {
          if (mounted) {
            setState(() => _albums =
                ((r['Items'] as List?) ?? []).cast<Map<String, dynamic>>());
          }
        })
        .catchError((_) {});
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_loadingPlay || !mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player'); // open instantly
    setState(() => _loadingPlay = true);
    try {
      final res = await JellyfinApi.getArtistAllTracks(widget.artistId);
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (items.isEmpty) return;
      final tracks = items.map(VibeTrack.fromJellyfin).toList();
      if (shuffle) tracks.shuffle();
      ref.read(audioHandlerProvider).playTracks(tracks, startIndex: 0);
    } catch (e) {
      debugPrint('ArtistScreen._playAll error: $e');
    } finally {
      if (mounted) setState(() => _loadingPlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme     = ref.watch(themeProvider);
    final screenW   = MediaQuery.of(context).size.width;
    final topPad    = MediaQuery.of(context).padding.top;
    final heroH  = 480.0;
    final cardW  = (screenW - 32 - 12) / 2;   // 2 columns, 12px gap
    final artUrl = JellyfinApi.imageUrl(widget.artistId, size: 600);

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
          // â”€â”€ Hero â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: SizedBox(
              height: heroH,
              child: Stack(
                children: [
                  // Hero image
                  Positioned(
                    top: 0, left: 0, right: 0,
                    height: screenW,
                    child: CachedNetworkImage(
                      imageUrl: artUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: theme.surface),
                      errorWidget: (_, _, _) => Container(color: theme.surface),
                    ),
                  ),

                  // Gradient overlay: transparent â†’ semi-dark â†’ background
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withAlpha(0x80),
                            theme.background,
                          ],
                          stops: const [0.3, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Back button
                  Positioned(
                    top: topPad + 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withAlpha(0x66),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                  // Artist name + album count at bottom of hero
                  Positioned(
                    left: 20, right: 20, bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.artistName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: theme.accent,
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        if (_albums.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_albums.length} album${_albums.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: theme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // â”€â”€ Discography grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_albums.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discography',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _playAll(),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: theme.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_loadingPlay)
                                    SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  else
                                    const Icon(Icons.play_arrow_rounded,
                                        color: Colors.white, size: 22),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Play All',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _playAll(shuffle: true),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.accent, width: 1.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shuffle_rounded,
                                      color: theme.accentBright, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Shuffle',
                                    style: TextStyle(
                                      color: theme.accentBright,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final album  = _albums[i];
                    final albumId = album['Id'] as String? ?? '';
                    final artUrl  = JellyfinApi.imageUrl(albumId, size: 400);
                    final year    = album['ProductionYear'] as int?;
                    return GestureDetector(
                      onTap: () {
                        final name = Uri.encodeComponent(
                            album['Name'] as String? ?? '');
                        final artist = Uri.encodeComponent(widget.artistName);
                        final yearParam = year != null ? '&year=$year' : '';
                        context.push(
                          '/album/$albumId?name=$name&artist=$artist$yearParam',
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: artUrl,
                              width: cardW,
                              height: cardW,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                width: cardW, height: cardW,
                                color: theme.surface,
                              ),
                              errorWidget: (_, _, _) => Container(
                                width: cardW, height: cardW,
                                color: theme.surface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album['Name'] as String? ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          if (year != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                '$year',
                                style: TextStyle(
                                  color: theme.accentBright.withAlpha(0xAA),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                  childCount: _albums.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 20,
                  childAspectRatio: cardW / (cardW + 72),
                ),
              ),
            ),
          ],
        ],
      ),
          // MiniPlayer stays visible while browsing the artist page
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}
