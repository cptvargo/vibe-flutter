import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

class PlaylistsTab extends ConsumerStatefulWidget {
  final VibeTheme theme;
  const PlaylistsTab({super.key, required this.theme});

  @override
  ConsumerState<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<PlaylistsTab> {
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await JellyfinApi.getPlaylists();
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _playlists = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPlaylist() async {
    final ctrl = TextEditingController();
    final name = await _nameDialog(ctrl);
    if (name == null || name.isEmpty) return;
    try {
      await JellyfinApi.createPlaylist(name);
      await _load();
    } catch (_) {}
  }

  Future<void> _deletePlaylist(Map<String, dynamic> playlist) async {
    final id   = playlist['Id']   as String;
    final name = playlist['Name'] as String? ?? 'Playlist';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111119),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Delete "$name"? This cannot be undone.',
            style: const TextStyle(color: Color(0xFF9090AA))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C5C78))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await JellyfinApi.deletePlaylist(id);
    await _load();
  }

  void _openPlaylist(Map<String, dynamic> playlist) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaylistSheet(
        playlist: playlist,
        theme: widget.theme,
        onReload: _load,
      ),
    );
  }

  Future<String?> _nameDialog(TextEditingController ctrl) =>
      showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111119),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Playlist',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            cursorColor: const Color(0xFFA855F7),
            decoration: const InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: Color(0xFF5C5C78)),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2E2E48))),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFA855F7))),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C5C78))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create',
                  style: TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.accentBright));
    }

    return Stack(
      children: [
        if (_playlists.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music_rounded, size: 56, color: theme.textFaint),
                const SizedBox(height: 12),
                Text('No playlists yet',
                    style: TextStyle(color: theme.textDim, fontSize: 15)),
                const SizedBox(height: 6),
                Text('Tap + to create one',
                    style: TextStyle(color: theme.textFaint, fontSize: 13)),
              ],
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: _playlists.length,
            itemBuilder: (_, i) {
              final pl        = _playlists[i];
              final id        = pl['Id']   as String? ?? '';
              final name      = pl['Name'] as String? ?? 'Playlist';
              final count     = pl['ChildCount'] as int? ?? 0;
              final tag       = (pl['ImageTags'] as Map?)?['Primary'] as String?;
              final artUrl    = JellyfinApi.imageUrl(id, size: 160, tag: tag);

              return GestureDetector(
                onTap: () => _openPlaylist(pl),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: theme.surface.withAlpha(0x99),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(12)),
                        child: CachedNetworkImage(
                          imageUrl: artUrl,
                          width: 64, height: 64,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                              width: 64, height: 64, color: theme.surface),
                          errorWidget: (_, _, _) => Container(
                            width: 64, height: 64, color: theme.surface,
                            child: Icon(Icons.queue_music_rounded,
                                color: theme.textFaint, size: 28),
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
                                style: TextStyle(
                                    color: theme.textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('$count ${count == 1 ? 'song' : 'songs'}',
                                style: TextStyle(
                                    color: theme.textDim, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            color: theme.textFaint, size: 20),
                        onPressed: () => _deletePlaylist(pl),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: theme.textFaint, size: 22),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              );
            },
          ),

        // Create playlist FAB
        Positioned(
          right: 20,
          bottom: 110,
          child: GestureDetector(
            onTap: _createPlaylist,
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: theme.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withAlpha(0x66),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Playlist detail sheet ──────────────────────────────────────────────────────

class _PlaylistSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;
  final VibeTheme theme;
  final VoidCallback onReload;

  const _PlaylistSheet({
    required this.playlist,
    required this.theme,
    required this.onReload,
  });

  @override
  ConsumerState<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<_PlaylistSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await JellyfinApi.getPlaylistItems(
          widget.playlist['Id'] as String);
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _playFrom(int index) {
    if (_items.isEmpty) return;
    final tracks = _items.map((i) => VibeTrack.fromJellyfin(i)).toList();
    final handler = ref.read(audioHandlerProvider);
    ref.read(playerOpenProvider.notifier).state = true;
    Navigator.of(context).pop();
    // ignore: use_build_context_synchronously
    context.push('/player');
    handler.playTracks(tracks, startIndex: index);
  }

  Future<void> _removeTrack(Map<String, dynamic> item) async {
    final playlistId = widget.playlist['Id'] as String;
    final entryId    = item['PlaylistItemId'] as String?;
    if (entryId == null) return;
    await JellyfinApi.removeFromPlaylist(playlistId, [entryId]);
    setState(() => _items.remove(item));
    widget.onReload();
  }

  Future<void> _openAddSongs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrackSearchSheet(
        playlistId: widget.playlist['Id'] as String,
        theme: widget.theme,
        onAdded: () async {
          await _load();
          widget.onReload();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme    = widget.theme;
    final name     = widget.playlist['Name'] as String? ?? 'Playlist';
    final count    = _items.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(0x33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                color: theme.textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('$count ${count == 1 ? 'song' : 'songs'}',
                            style: TextStyle(
                                color: theme.textDim, fontSize: 13)),
                      ],
                    ),
                  ),
                  // Play all
                  if (_items.isNotEmpty)
                    GestureDetector(
                      onTap: () => _playFrom(0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 9),
                        decoration: BoxDecoration(
                          color: theme.accent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: theme.accent.withAlpha(0x55),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 4),
                            Text('Play All',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E1E30), height: 1),
            // Track list
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: theme.accentBright))
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.music_note_rounded,
                                  size: 44, color: theme.textFaint),
                              const SizedBox(height: 8),
                              Text('No songs yet',
                                  style: TextStyle(
                                      color: theme.textDim, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text('Tap Add Songs to get started',
                                  style: TextStyle(
                                      color: theme.textFaint, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: ctrl,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item   = _items[i];
                            final title  = item['Name']        as String? ?? '';
                            final artist = item['AlbumArtist'] as String?
                                ?? (item['Artists'] as List?)?.firstOrNull
                                    as String? ?? '';

                            return Dismissible(
                              key: ValueKey(item['PlaylistItemId'] ?? item['Id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.redAccent.withAlpha(0x33),
                                child: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent),
                              ),
                              onDismissed: (_) => _removeTrack(item),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 2),
                                leading: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                      color: theme.textFaint,
                                      fontSize: 13,
                                      fontVariations: const [
                                        FontVariation('wght', 500)
                                      ]),
                                ),
                                title: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.textColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text(artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.textDim, fontSize: 12)),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline_rounded,
                                      color: theme.textFaint, size: 20),
                                  onPressed: () => _removeTrack(item),
                                ),
                                onTap: () => _playFrom(i),
                              ),
                            );
                          },
                        ),
            ),
            // Add songs button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GestureDetector(
                  onTap: _openAddSongs,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: theme.accentBright.withAlpha(0x44)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded,
                            color: theme.accentBright, size: 20),
                        const SizedBox(width: 6),
                        Text('Add Songs',
                            style: TextStyle(
                                color: theme.accentBright,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
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

// ── Track search sheet ─────────────────────────────────────────────────────────

class _TrackSearchSheet extends StatefulWidget {
  final String playlistId;
  final VibeTheme theme;
  final Future<void> Function() onAdded;

  const _TrackSearchSheet({
    required this.playlistId,
    required this.theme,
    required this.onAdded,
  });

  @override
  State<_TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends State<_TrackSearchSheet> {
  final _ctrl    = TextEditingController();
  Timer?  _debounce;
  List<Map<String, dynamic>> _results = [];
  final Set<String> _added = {};
  bool _searching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await JellyfinApi.searchTracks(q.trim());
        if (mounted) setState(() { _results = results; _searching = false; });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _add(Map<String, dynamic> item) async {
    final id = item['Id'] as String;
    if (_added.contains(id)) return;
    setState(() => _added.add(id));
    try {
      await JellyfinApi.addToPlaylist(widget.playlistId, [id]);
      await widget.onAdded();
    } catch (_) {
      if (mounted) setState(() => _added.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(0x33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onQuery,
                  style: TextStyle(color: theme.textColor, fontSize: 15),
                  cursorColor: theme.accentBright,
                  decoration: InputDecoration(
                    hintText: 'Search songs…',
                    hintStyle: TextStyle(color: theme.textFaint),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: theme.textFaint, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _searching
                  ? Center(
                      child: CircularProgressIndicator(
                          color: theme.accentBright))
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _ctrl.text.isEmpty
                                ? 'Search your library'
                                : 'No results',
                            style: TextStyle(
                                color: theme.textFaint, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          controller: ctrl,
                          padding: const EdgeInsets.only(bottom: 40),
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final item    = _results[i];
                            final id      = item['Id']          as String? ?? '';
                            final title   = item['Name']        as String? ?? '';
                            final artist  = item['AlbumArtist'] as String?
                                ?? (item['Artists'] as List?)
                                    ?.firstOrNull as String? ?? '';
                            final added   = _added.contains(id);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 2),
                              title: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: theme.textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text(artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: theme.textDim, fontSize: 12)),
                              trailing: added
                                  ? Icon(Icons.check_circle_rounded,
                                      color: theme.accentBright, size: 22)
                                  : Icon(Icons.add_circle_outline_rounded,
                                      color: theme.textFaint, size: 22),
                              onTap: () => _add(item),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
