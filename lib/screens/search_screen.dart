import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';
import '../widgets/artist_avatar.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl     = TextEditingController();
  Timer? _debounce;
  bool _loading   = false;
  bool _searched  = false;

  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _albums  = [];
  List<Map<String, dynamic>> _tracks  = [];

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() { _artists = []; _albums = []; _tracks = []; _searched = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(trimmed));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res   = await JellyfinApi.search(q, limit: 60);
      final items = (res['Items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted) return;
      setState(() {
        _artists = items.where((i) => i['Type'] == 'MusicArtist').toList();
        _albums  = items.where((i) => i['Type'] == 'MusicAlbum').toList();
        _tracks  = items.where((i) => i['Type'] == 'Audio').toList();
        _loading  = false;
        _searched = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playTrack(Map<String, dynamic> raw) async {
    if (!mounted) return;
    final track = VibeTrack.fromJellyfin(raw);
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks([track]);
  }

  void _clearSearch() {
    _ctrl.clear();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final hasResults = _artists.isNotEmpty || _albums.isNotEmpty || _tracks.isNotEmpty;

    return Column(
      children: [
        // ── Search bar ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onChanged,
            style: TextStyle(color: theme.textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Artists, albums, tracks…',
              hintStyle: TextStyle(color: theme.textFaint, fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded, color: theme.textFaint, size: 22),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: _clearSearch,
                      child: Icon(Icons.cancel_rounded,
                          color: theme.textFaint, size: 18),
                    )
                  : null,
              filled: true,
              fillColor: theme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // ── Results ─────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: theme.accentBright))
              : !_searched
                  ? _Prompt(theme: theme)
                  : !hasResults
                      ? _NoResults(query: _ctrl.text, theme: theme)
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 110),
                          children: [
                            if (_artists.isNotEmpty) ...[
                              _SectionLabel('Artists', theme: theme),
                              ..._artists.map((a) => _ArtistRow(
                                item: a,
                                theme: theme,
                                onTap: () => context.push(
                                  '/artist/${a['Id']}?name='
                                  '${Uri.encodeComponent(a['Name'] as String? ?? '')}',
                                ),
                              )),
                            ],
                            if (_albums.isNotEmpty) ...[
                              _SectionLabel('Albums', theme: theme),
                              ..._albums.map((a) {
                                final name   = Uri.encodeComponent(a['Name']        as String? ?? '');
                                final artist = Uri.encodeComponent(a['AlbumArtist'] as String? ?? '');
                                final year   = a['ProductionYear'] as int?;
                                final yParam = year != null ? '&year=$year' : '';
                                return _AlbumRow(
                                  item: a,
                                  theme: theme,
                                  onTap: () => context.push(
                                    '/album/${a['Id']}?name=$name&artist=$artist$yParam',
                                  ),
                                );
                              }),
                            ],
                            if (_tracks.isNotEmpty) ...[
                              _SectionLabel('Tracks', theme: theme),
                              ..._tracks.map((t) => _TrackRow(
                                item: t,
                                theme: theme,
                                onTap: () => _playTrack(t),
                              )),
                            ],
                          ],
                        ),
        ),
      ],
    );
  }
}

// ── Section label ───────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final VibeTheme theme;
  const _SectionLabel(this.text, {required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: theme.accentBright,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 0.5, color: theme.accentBright.withAlpha(0x2A))),
        ],
      ),
    );
  }
}

// ── Artist row ──────────────────────────────────────────────────────────────
class _ArtistRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final VoidCallback onTap;
  const _ArtistRow({required this.item, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id   = item['Id']   as String? ?? '';
    final name = item['Name'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ArtistAvatar(id: id, name: name, size: 48, theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textColor, fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Album row ───────────────────────────────────────────────────────────────
class _AlbumRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final VoidCallback onTap;
  const _AlbumRow({required this.item, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id     = item['Id']          as String? ?? '';
    final name   = item['Name']        as String? ?? '';
    final artist = item['AlbumArtist'] as String?
        ?? (item['Artists'] as List?)?.firstOrNull as String? ?? '';
    final url    = JellyfinApi.imageUrl(id, size: 100);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 48, height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(width: 48, height: 48, color: theme.surface),
                errorWidget: (_, _, _) => Container(
                  width: 48, height: 48, color: theme.surface,
                  child: Icon(Icons.album_rounded, color: theme.textFaint, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textColor, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textDim, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Track row ───────────────────────────────────────────────────────────────
class _TrackRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final VoidCallback onTap;
  const _TrackRow({required this.item, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final albumId = item['AlbumId'] as String?
        ?? item['ParentId'] as String?
        ?? item['Id']       as String? ?? '';
    final name   = item['Name'] as String? ?? '';
    final artist = item['AlbumArtist'] as String?
        ?? (item['Artists'] as List?)?.firstOrNull as String? ?? '';
    final url    = JellyfinApi.imageUrl(albumId, size: 100);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: url,
                width: 48, height: 48,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(width: 48, height: 48, color: theme.surface),
                errorWidget: (_, _, _) => Container(
                  width: 48, height: 48, color: theme.surface,
                  child: Icon(Icons.music_note_rounded, color: theme.textFaint, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textColor, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textDim, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline_rounded, color: theme.accentBright, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Empty states ────────────────────────────────────────────────────────────
class _Prompt extends StatelessWidget {
  final VibeTheme theme;
  const _Prompt({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 52, color: theme.textFaint),
          const SizedBox(height: 16),
          Text('Search your library',
              style: TextStyle(color: theme.textDim, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Artists, albums, or tracks',
              style: TextStyle(color: theme.textFaint, fontSize: 13)),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final VibeTheme theme;
  const _NoResults({required this.query, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off_rounded, size: 48, color: theme.textFaint),
          const SizedBox(height: 16),
          Text('No results for "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textDim, fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Try a different spelling',
              style: TextStyle(color: theme.textFaint, fontSize: 13)),
        ],
      ),
    );
  }
}
