import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../providers.dart';

class PostPlaybackScreen extends ConsumerWidget {
  final String artistId;
  final String artistName;
  final String title;
  final String artUrl;

  const PostPlaybackScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    required this.title,
    required this.artUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(playerThemeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                children: [
                  // Small album art
                  if (artUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: artUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: theme.accent.withAlpha(0x44),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),

                  const SizedBox(height: 20),

                  Text(
                    'If you enjoyed',
                    style: TextStyle(
                      color: Colors.white.withAlpha(0x88),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'YOU MIGHT ALSO LIKE',
                    style: TextStyle(
                      color: Colors.white.withAlpha(0x55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Similar Artists ───────────────────────────────────────────────
            Expanded(
              child: artistId.isEmpty
                  ? const _EmptyState()
                  : _SimilarArtistsList(
                      artistId: artistId,
                      theme: theme,
                    ),
            ),

            // ── Back to Home ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withAlpha(0x18),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Similar artists grid ────────────────────────────────────────────────────

class _SimilarArtistsList extends StatefulWidget {
  final String  artistId;
  final dynamic theme;

  const _SimilarArtistsList({required this.artistId, required this.theme});

  @override
  State<_SimilarArtistsList> createState() => _SimilarArtistsListState();
}

class _SimilarArtistsListState extends State<_SimilarArtistsList> {
  List<Map<String, dynamic>> _artists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    JellyfinApi.getSimilarArtistsByGenre(widget.artistId).then((list) {
      if (mounted) setState(() { _artists = list; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white30));
    }
    if (_artists.isEmpty) return const _EmptyState();

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: _artists.length,
      itemBuilder: (context, i) {
        final a    = _artists[i];
        final id   = a['Id']   as String? ?? '';
        final name = a['Name'] as String? ?? '';
        return _ArtistTile(
          id: id,
          name: name,
          theme: widget.theme,
          onTap: () => context.go('/artist/$id?name=${Uri.encodeComponent(name)}'),
        );
      },
    );
  }
}

class _ArtistTile extends StatelessWidget {
  final String  id;
  final String  name;
  final dynamic theme;
  final VoidCallback onTap;

  const _ArtistTile({
    required this.id,
    required this.name,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withAlpha(0x18),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 46,
              backgroundColor: Colors.white.withAlpha(0x18),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: JellyfinApi.imageUrl(id, size: 120),
                  width: 92, height: 92,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No similar artists found',
        style: TextStyle(color: Colors.white.withAlpha(0x55), fontSize: 14),
      ),
    );
  }
}
