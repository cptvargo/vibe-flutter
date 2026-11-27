import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../providers.dart';
import '../services/download_service.dart';
import '../services/offline_playlist_service.dart';
import '../theme/vibe_theme.dart';
import '../widgets/vibe_ui.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int    _tab           = 0;
  bool   _searchVisible = false;
  String _searchQuery   = '';
  final _searchCtrl     = TextEditingController();
  List<Map<String, dynamic>> _downloads = [];
  List<Map<String, dynamic>> _playlists = [];
  int    _storageBytes = 0;
  bool   _calcStorage  = false;

  StreamSubscription<void>? _dlSub;
  StreamSubscription<void>? _plSub;

  @override
  void initState() {
    super.initState();
    _reload();
    _dlSub = DownloadService.onChange.listen((_) => _reload());
    _plSub = OfflinePlaylistService.onChange.listen((_) {
      if (mounted) setState(() => _playlists = OfflinePlaylistService.getPlaylists());
    });
  }

  @override
  void dispose() {
    _dlSub?.cancel();
    _plSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _downloads   = DownloadService.getDownloads();
      _playlists   = OfflinePlaylistService.getPlaylists();
      _calcStorage = true;
    });
    final bytes = await DownloadService.storageUsedBytes();
    if (mounted) setState(() { _storageBytes = bytes; _calcStorage = false; });
  }

  // Sort a track list by disc number then track number — the canonical
  // Jellyfin album order. This is the ONLY ordering used for playback.
  static List<Map<String, dynamic>> _byDiscTrack(List<Map<String, dynamic>> tracks) {
    return [...tracks]..sort((a, b) {
        final discCmp = (a['discNumber'] as int? ?? 1)
            .compareTo(b['discNumber'] as int? ?? 1);
        if (discCmp != 0) return discCmp;
        return (a['trackNumber'] as int? ?? 0)
            .compareTo(b['trackNumber'] as int? ?? 0);
      });
  }

  List<Map<String, dynamic>> get _filteredDownloads {
    if (_searchQuery.isEmpty) return _downloads;
    final q = _searchQuery.toLowerCase();
    return _downloads.where((d) =>
      (d['title']  as String? ?? '').toLowerCase().contains(q) ||
      (d['artist'] as String? ?? '').toLowerCase().contains(q) ||
      (d['album']  as String? ?? '').toLowerCase().contains(q),
    ).toList();
  }

  // Groups flat download list by albumId. Each group is sorted by
  // disc + track number using stored Jellyfin metadata.
  List<List<Map<String, dynamic>>> get _albums {
    final map   = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final d in _filteredDownloads) {
      final key = (d['albumId'] as String?) ?? (d['itemId'] as String);
      if (!map.containsKey(key)) order.add(key);
      map.putIfAbsent(key, () => []).add(d);
    }
    return order.map((k) => _byDiscTrack(map[k]!)).toList();
  }

  // Groups album-groups by their album artist, sorted alphabetically.
  // Prefers stored 'albumArtist' field (new downloads); falls back to
  // the primary artist name for older downloads.
  Map<String, List<List<Map<String, dynamic>>>> get _byArtist {
    final map   = <String, List<List<Map<String, dynamic>>>>{};
    final order = <String>[];
    for (final group in _albums) {
      final stored = group.first['albumArtist'] as String?;
      final artist = stored?.isNotEmpty == true
          ? stored!
          : (group.first['artist'] as String? ?? 'Unknown')
              .split(RegExp(r'\s+feat\.|\s+&\s+')).first.trim();
      if (!map.containsKey(artist)) order.add(artist);
      map.putIfAbsent(artist, () => []).add(group);
    }
    final sorted = [...order]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Map.fromEntries(sorted.map((k) => MapEntry(k, map[k]!)));
  }

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024)         return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  void _playAlbumGroup(List<Map<String, dynamic>> group, {int startIndex = 0}) {
    if (group.isEmpty) return;
    // Always enforce disc+track ordering before building the queue.
    // The group passed in may have been sorted already, but this is a
    // cheap no-op and guarantees correct order regardless of how the
    // group was assembled (card tap, sheet tap, Play All).
    final sorted = _byDiscTrack(group);
    final tracks = sorted.map(DownloadService.trackFromData).toList();
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks, startIndex: startIndex);
  }

  void _playAll() {
    if (_downloads.isEmpty) return;
    final tracks = _albums.expand((g) => g).map(DownloadService.trackFromData).toList();
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks);
  }

  void _shuffleAll() {
    if (_downloads.isEmpty) return;
    final tracks = _albums.expand((g) => g).map(DownloadService.trackFromData).toList()..shuffle();
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks);
  }

  Future<void> _showAlbumTracks(List<Map<String, dynamic>> storedGroup) async {
    final albumId = storedGroup.first['albumId'] as String?;
    List<Map<String, dynamic>> group;

    try {
      // Jellyfin is the authoritative source for album track ordering.
      // Fetch the full track list sorted by IndexNumber, then build the
      // playback group from only the downloaded tracks in that exact order.
      if (albumId == null) throw Exception('no albumId');
      final result        = await JellyfinApi.getAlbumTracks(albumId);
      final jellyfinItems = (result['Items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final ordered = <Map<String, dynamic>>[];
      for (final jItem in jellyfinItems) {
        final itemId   = jItem['Id']                  as String;
        final discNum  = jItem['ParentIndexNumber']   as int? ?? 1;
        final trackNum = jItem['IndexNumber']         as int? ?? 0;
        final stored   = DownloadService.getDownloadData(itemId);
        if (stored == null) continue; // track not downloaded

        ordered.add({...stored, 'discNumber': discNum, 'trackNumber': trackNum});

        // Persist correct disc/track numbers back to Hive.
        DownloadService.updateTrackMetadata(itemId, {
          'discNumber':  discNum,
          'trackNumber': trackNum,
        });
      }

      group = ordered.isNotEmpty ? ordered : _byDiscTrack(storedGroup);
    } catch (_) {
      // Offline or API error: fall back to stored disc+track sort.
      group = _byDiscTrack(storedGroup);
    }

    if (!mounted) return;
    final theme = ref.read(themeProvider);
    showModalBottomSheet<void>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _OfflineAlbumSheet(
        group:  group,
        theme:  theme,
        onPlay: (startIndex) => _playAlbumGroup(group, startIndex: startIndex),
      ),
    );
  }

  Future<void> _deleteAlbumGroup(List<Map<String, dynamic>> group) async {
    for (final d in group) {
      final id = d['itemId'] as String;
      for (final pl in _playlists) {
        await OfflinePlaylistService.removeTrack(pl['id'] as String, id);
      }
      await DownloadService.deleteDownload(id);
    }
  }

  void _playPlaylist(String id) {
    final tracks = OfflinePlaylistService.getPlaylistTracks(id);
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This playlist has no downloaded tracks')),
      );
      return;
    }
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks);
  }

  Future<void> _showCreatePlaylist() async {
    final ctrl = TextEditingController();
    final name = await _nameDialog('New Playlist', 'Playlist name', ctrl);
    if (name == null || name.isEmpty) return;
    final id = await OfflinePlaylistService.createPlaylist(name);
    if (mounted && _downloads.isNotEmpty) {
      await _showSongPicker(id);
    }
  }

  Future<void> _showRenamePlaylist(String id, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await _nameDialog('Rename Playlist', 'Playlist name', ctrl);
    if (name != null && name.isNotEmpty && name != current) {
      await OfflinePlaylistService.renamePlaylist(id, name);
    }
  }

  Future<void> _showSongPicker(String playlistId) async {
    final theme = ref.read(themeProvider);
    final sorted = [..._downloads]..sort((a, b) {
        final aa = '${a['artist'] ?? ''}${a['album'] ?? ''}${a['trackNumber'] ?? 0}';
        final bb = '${b['artist'] ?? ''}${b['album'] ?? ''}${b['trackNumber'] ?? 0}';
        return aa.toLowerCase().compareTo(bb.toLowerCase());
      });
    await showModalBottomSheet<void>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _SongPickerSheet(
        playlistId: playlistId,
        downloads:  sorted,
        theme:      theme,
      ),
    );
  }

  Future<String?> _nameDialog(
      String title, String hint, TextEditingController ctrl) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111119),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller:  ctrl,
          autofocus:   true,
          style:       const TextStyle(color: Colors.white),
          cursorColor: const Color(0xFFA855F7),
          decoration: InputDecoration(
            hintText:      hint,
            hintStyle:     const TextStyle(color: Color(0xFF5C5C78)),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2E2E48))),
            focusedBorder: const UnderlineInputBorder(
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
            child: const Text('Save',
                style: TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = ref.watch(themeProvider);
    final albums = _albums;

    final byArtist = _byArtist;
    final subtitle = _downloads.isEmpty
        ? 'No downloads yet'
        : _calcStorage
            ? '${byArtist.length} ${byArtist.length == 1 ? 'artist' : 'artists'}  ·  ${albums.length} albums  ·  …'
            : '${byArtist.length} ${byArtist.length == 1 ? 'artist' : 'artists'}  ·  ${albums.length} albums  ·  ${_fmt(_storageBytes)}';

    return Stack(
      children: [
        ColoredBox(
          color: theme.background,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Offline Hub',
                                style: TextStyle(
                                  color: theme.textColor, fontSize: 26,
                                  fontWeight: FontWeight.w800, letterSpacing: 0.2,
                                  shadows: [
                                    Shadow(color: theme.accent.withAlpha(0xAA), blurRadius: 12),
                                  ],
                                )),
                          ),
                          IconButton(
                            icon: Icon(
                              _searchVisible ? Icons.close_rounded : Icons.search_rounded,
                              color: _searchVisible ? theme.accentBright : theme.textFaint,
                              size: 22,
                            ),
                            onPressed: () => setState(() {
                              _searchVisible = !_searchVisible;
                              if (!_searchVisible) { _searchQuery = ''; _searchCtrl.clear(); }
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: theme.textFaint, fontSize: 12)),
                      if (_storageBytes > 0) ...[
                        const SizedBox(height: 8),
                        _StorageBar(
                          usedBytes:     _storageBytes,
                          formattedSize: _fmt(_storageBytes),
                          theme:         theme,
                        ),
                      ],
                    ],
                  ),
                ),

                if (_searchVisible)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: TextField(
                      controller:  _searchCtrl,
                      onChanged:   (v) => setState(() => _searchQuery = v),
                      autofocus:   true,
                      style:       TextStyle(color: theme.textColor, fontSize: 14),
                      cursorColor: theme.accentBright,
                      decoration: InputDecoration(
                        hintText:  'Artists, albums, tracks…',
                        hintStyle: TextStyle(color: theme.textFaint, fontSize: 14),
                        filled:    true,
                        fillColor: theme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: theme.textFaint, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:   BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(children: [
                    _Chip(label: 'Albums',    count: albums.length,      active: _tab == 0,
                        theme: theme, onTap: () => setState(() => _tab = 0)),
                    const SizedBox(width: 10),
                    _Chip(label: 'Artists',   count: byArtist.length,    active: _tab == 1,
                        theme: theme, onTap: () => setState(() => _tab = 1)),
                    const SizedBox(width: 10),
                    _Chip(label: 'Playlists', count: _playlists.length,  active: _tab == 2,
                        theme: theme, onTap: () => setState(() => _tab = 2)),
                  ]),
                ),

                Expanded(
                  child: _tab == 0
                      ? _AlbumsTab(
                          albums:         albums,
                          theme:          theme,
                          onPlayAll:      _playAll,
                          onShuffleAll:   _shuffleAll,
                          onShowTracks:   _showAlbumTracks,
                          onPlayAlbum:    (g) => _playAlbumGroup(g),
                          onDelete:       _deleteAlbumGroup,
                        )
                      : _tab == 1
                      ? _ArtistsTab(
                          byArtist:     byArtist,
                          theme:        theme,
                          onShowTracks: _showAlbumTracks,
                          onPlayAlbum:  (g) => _playAlbumGroup(g),
                          onDelete:     _deleteAlbumGroup,
                        )
                      : _PlaylistsTab(
                          playlists:   _playlists,
                          theme:       theme,
                          onCreate:    _showCreatePlaylist,
                          onPlay:      _playPlaylist,
                          onRename:    _showRenamePlaylist,
                          onEditSongs: _showSongPicker,
                          onDelete:    OfflinePlaylistService.deletePlaylist,
                        ),
                ),
              ],
            ),
          ),
        ),
        _DownloadPill(theme: theme),
      ],
    );
  }
}

// ── Tab chip ──────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String     label;
  final int        count;
  final bool       active;
  final VibeTheme  theme;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color:        active ? theme.accent : theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? theme.accent : theme.accent.withAlpha(0x33),
        ),
        boxShadow: active
            ? [BoxShadow(color: theme.accent.withAlpha(0x44), blurRadius: 10)]
            : null,
      ),
      child: Text(
        count > 0 ? '$label  $count' : label,
        style: TextStyle(
          color:      active ? Colors.white : theme.textFaint,
          fontSize:   13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

// ── Albums tab ────────────────────────────────────────────────────────────────

class _AlbumsTab extends StatelessWidget {
  final List<List<Map<String, dynamic>>> albums;
  final VibeTheme  theme;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffleAll;
  final void Function(List<Map<String, dynamic>>) onShowTracks;
  final void Function(List<Map<String, dynamic>>) onPlayAlbum;
  final Future<void> Function(List<Map<String, dynamic>>) onDelete;

  const _AlbumsTab({
    required this.albums,
    required this.theme,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onShowTracks,
    required this.onPlayAlbum,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return _EmptyState(
        icon:    Icons.album_outlined,
        message: 'No downloaded albums',
        sub:     'Open any album and tap ↓ to save it for offline listening',
        theme:   theme,
      );
    }
    final bottom = MediaQuery.of(context).padding.bottom;
    return CustomScrollView(
      slivers: [
        // ── Play All + Shuffle row ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(
                child: VibeBounce(
                  onTap: onPlayAll,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color:        theme.accent,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(
                          color: theme.accent.withAlpha(0x55), blurRadius: 14)],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text('Play All',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VibeBounce(
                  onTap: onShuffleAll,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color:        theme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: theme.accent.withAlpha(0x77)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shuffle_rounded,
                            color: theme.accentBright, size: 18),
                        const SizedBox(width: 6),
                        Text('Shuffle',
                            style: TextStyle(color: theme.accentBright,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),

        // ── Just Added horizontal shelf ─────────────────────────────────────
        if (albums.length >= 2) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Just Added',
                  style: TextStyle(
                      color:       theme.textFaint,
                      fontSize:    11,
                      fontWeight:  FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:         const EdgeInsets.fromLTRB(16, 0, 16, 0),
                itemCount:       albums.length.clamp(0, 5),
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _JustAddedCard(
                  group: albums[i],
                  theme: theme,
                  onTap:  () => onShowTracks(albums[i]),
                  onPlay: () => onPlayAlbum(albums[i]),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text('All Albums',
                  style: TextStyle(
                      color:       theme.textFaint,
                      fontSize:    11,
                      fontWeight:  FontWeight.w700,
                      letterSpacing: 0.6)),
            ),
          ),
        ],

        // ── 2-column album grid ─────────────────────────────────────────────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 100),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final group = albums[index];
                return _AlbumCard(
                  group:        group,
                  theme:        theme,
                  onShowTracks: () => onShowTracks(group),
                  onPlayAlbum:  () => onPlayAlbum(group),
                  onDelete:     () => onDelete(group),
                );
              },
              childCount: albums.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   2,
              crossAxisSpacing: 12,
              mainAxisSpacing:  12,
              childAspectRatio: 0.76,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Album grid card ───────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  final List<Map<String, dynamic>> group;
  final VibeTheme   theme;
  final VoidCallback onShowTracks;
  final VoidCallback onPlayAlbum;
  final VoidCallback onDelete;

  const _AlbumCard({
    required this.group,
    required this.theme,
    required this.onShowTracks,
    required this.onPlayAlbum,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final first  = group.first;
    final artUrl = first['artworkUrl'] as String? ?? '';
    final name   = first['album']     as String? ?? 'Unknown Album';
    final artist = first['artist']    as String? ?? '';
    final n      = group.length;

    return VibeBounce(
      onTap: onShowTracks,
      child: Container(
          decoration: BoxDecoration(
            color:        theme.tint1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.accent.withAlpha(0x28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork fills top portion of the card
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13)),
                      child: artUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl:    artUrl,
                              fit:         BoxFit.cover,
                              width:       double.infinity,
                              placeholder: (_, _) => Container(color: theme.surface),
                              errorWidget: (_, _, _) => Container(
                                color: theme.surface,
                                child: Icon(Icons.album_outlined,
                                    color: theme.textFaint, size: 36),
                              ),
                            )
                          : Container(
                              color: theme.surface,
                              child: Icon(Icons.album_outlined,
                                  color: theme.textFaint, size: 36),
                            ),
                    ),
                    // Floating play button
                    Positioned(
                      bottom: 8, right: 8,
                      child: GestureDetector(
                        onTap:    onPlayAlbum,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color:  theme.accent,
                            shape:  BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withAlpha(0xAA),
                                  blurRadius: 8),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Album info + trash
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 6, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: theme.textColor, fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '$artist  ·  $n ${n == 1 ? 'track' : 'tracks'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap:    onDelete,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            color: theme.textFaint.withAlpha(0x99), size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }
}

// ── Just Added horizontal card ────────────────────────────────────────────────

class _JustAddedCard extends StatelessWidget {
  final List<Map<String, dynamic>> group;
  final VibeTheme    theme;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _JustAddedCard({
    required this.group,
    required this.theme,
    required this.onTap,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final first  = group.first;
    final artUrl = first['artworkUrl'] as String? ?? '';
    final name   = first['album']     as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: artUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl:    artUrl,
                          width: 120, height: 120, fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(width: 120, height: 120, color: theme.surface),
                          errorWidget: (_, _, _) => Container(
                            width: 120, height: 120, color: theme.surface,
                            child: Icon(Icons.album_outlined,
                                color: theme.textFaint, size: 36),
                          ),
                        )
                      : Container(
                          width: 120, height: 120, color: theme.surface,
                          child: Icon(Icons.album_outlined,
                              color: theme.textFaint, size: 36),
                        ),
                ),
                Positioned(
                  bottom: 6, right: 6,
                  child: GestureDetector(
                    onTap:    onPlay,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color:  theme.accent,
                        shape:  BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(0xAA), blurRadius: 6),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textColor, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Artists tab ───────────────────────────────────────────────────────────────

class _ArtistsTab extends StatelessWidget {
  final Map<String, List<List<Map<String, dynamic>>>> byArtist;
  final VibeTheme theme;
  final void Function(List<Map<String, dynamic>>) onShowTracks;
  final void Function(List<Map<String, dynamic>>) onPlayAlbum;
  final Future<void> Function(List<Map<String, dynamic>>) onDelete;

  const _ArtistsTab({
    required this.byArtist,
    required this.theme,
    required this.onShowTracks,
    required this.onPlayAlbum,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (byArtist.isEmpty) {
      return _EmptyState(
        icon:    Icons.person_outline,
        message: 'No downloaded artists',
        sub:     'Open any album and tap ↓ to save it for offline listening',
        theme:   theme,
      );
    }
    final entries = byArtist.entries.toList();
    return ListView.builder(
      padding: EdgeInsets.only(
          top: 8, bottom: MediaQuery.of(context).padding.bottom + 100),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry  = entries[i];
        final name   = entry.key;
        final albums = entry.value;
        final totalTracks = albums.fold(0, (s, g) => s + g.length);
        final artUrls = albums
            .map((g) => g.first['artworkUrl'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .take(4)
            .toList();

        return _ArtistRow(
          name:        name,
          albums:      albums,
          artUrls:     artUrls,
          totalTracks: totalTracks,
          theme:       theme,
          onTap: () => _openArtistHero(context, name, albums),
        );
      },
    );
  }

  void _openArtistHero(
      BuildContext context, String name, List<List<Map<String, dynamic>>> albums) {
    showModalBottomSheet<void>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _ArtistHeroSheet(
        name:         name,
        albums:       albums,
        theme:        theme,
        onShowTracks: onShowTracks,
        onPlayAlbum:  onPlayAlbum,
        onDelete:     onDelete,
      ),
    );
  }
}

// ── Artist row ────────────────────────────────────────────────────────────────

class _ArtistRow extends StatelessWidget {
  final String    name;
  final List<List<Map<String, dynamic>>> albums;
  final List<String>  artUrls;
  final int       totalTracks;
  final VibeTheme theme;
  final VoidCallback  onTap;

  const _ArtistRow({
    required this.name,
    required this.albums,
    required this.artUrls,
    required this.totalTracks,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return VibeBounce(
      onTap: onTap,
      child: Container(
        margin:  const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        theme.tint1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.accent.withAlpha(0x28)),
        ),
        child: Row(
          children: [
            _MosaicAvatar(artUrls: artUrls, size: 56, theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textColor, fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    '${albums.length} ${albums.length == 1 ? 'album' : 'albums'}  ·  $totalTracks tracks',
                    style: TextStyle(color: theme.textFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: theme.textFaint.withAlpha(0x88), size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Mosaic avatar (2×2 album art grid) ───────────────────────────────────────

class _MosaicAvatar extends StatelessWidget {
  final List<String> artUrls;
  final double       size;
  final VibeTheme    theme;

  const _MosaicAvatar({
    required this.artUrls,
    required this.size,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    if (artUrls.isEmpty) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(color: theme.surface, borderRadius: radius),
        child: Icon(Icons.person_rounded, color: theme.textFaint, size: size * 0.5),
      );
    }
    if (artUrls.length == 1) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: artUrls[0], width: size, height: size, fit: BoxFit.cover,
          placeholder: (_, _) =>
              Container(width: size, height: size, color: theme.surface),
          errorWidget: (_, _, _) => Container(
            width: size, height: size, color: theme.surface,
            child: Icon(Icons.person_rounded, color: theme.textFaint, size: size * 0.5),
          ),
        ),
      );
    }
    // 2×2 mosaic
    final urls = artUrls.take(4).toList();
    final half = size / 2;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size, height: size,
        child: Wrap(
          children: List.generate(4, (i) {
            final url = i < urls.length ? urls[i] : '';
            return url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url, width: half, height: half, fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(width: half, height: half, color: theme.tint1),
                    errorWidget: (_, _, _) =>
                        Container(width: half, height: half, color: theme.tint1),
                  )
                : Container(width: half, height: half, color: theme.tint1);
          }),
        ),
      ),
    );
  }
}

// ── Artist hero sheet ─────────────────────────────────────────────────────────

class _ArtistHeroSheet extends ConsumerWidget {
  final String    name;
  final List<List<Map<String, dynamic>>> albums;
  final VibeTheme theme;
  final void Function(List<Map<String, dynamic>>) onShowTracks;
  final void Function(List<Map<String, dynamic>>) onPlayAlbum;
  final Future<void> Function(List<Map<String, dynamic>>) onDelete;

  const _ArtistHeroSheet({
    required this.name,
    required this.albums,
    required this.theme,
    required this.onShowTracks,
    required this.onPlayAlbum,
    required this.onDelete,
  });

  static List<Map<String, dynamic>> _sortedGroup(List<Map<String, dynamic>> g) =>
      [...g]..sort((a, b) {
          final d = (a['discNumber'] as int? ?? 1)
              .compareTo(b['discNumber'] as int? ?? 1);
          if (d != 0) return d;
          return (a['trackNumber'] as int? ?? 0)
              .compareTo(b['trackNumber'] as int? ?? 0);
        });

  void _playAll(BuildContext context, WidgetRef ref) {
    final tracks = albums
        .expand((g) => _sortedGroup(g))
        .map(DownloadService.trackFromData)
        .toList();
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks);
  }

  void _shuffleAll(BuildContext context, WidgetRef ref) {
    final tracks = albums
        .expand((g) => _sortedGroup(g))
        .map(DownloadService.trackFromData)
        .toList()..shuffle();
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(tracks);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroArtUrl  = albums.first.first['artworkUrl'] as String? ?? '';
    final totalTracks = albums.fold(0, (s, g) => s + g.length);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     1.0,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color:        Color(0xFF0E0E18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            // ── Hero header ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 272,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (heroArtUrl.isNotEmpty)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                        child: CachedNetworkImage(
                          imageUrl: heroArtUrl, fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              const ColoredBox(color: Color(0xFF1A1A2E)),
                          errorWidget: (_, _, _) =>
                              const ColoredBox(color: Color(0xFF1A1A2E)),
                        ),
                      )
                    else
                      const ColoredBox(color: Color(0xFF1A1A2E)),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end:   Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0xFF0E0E18)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color:        Colors.white.withAlpha(0x44),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Positioned(
                      bottom: 20, left: 20, right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                color:      Colors.white,
                                fontSize:   32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              )),
                          const SizedBox(height: 4),
                          Text(
                            '${albums.length} ${albums.length == 1 ? 'album' : 'albums'}  ·  $totalTracks tracks',
                            style: TextStyle(color: Colors.white.withAlpha(0x99), fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                              child: VibeBounce(
                                onTap: () => _playAll(context, ref),
                                child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color:        theme.accent,
                                    borderRadius: BorderRadius.circular(21),
                                    boxShadow: [BoxShadow(
                                        color: theme.accent.withAlpha(0x66),
                                        blurRadius: 12)],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.play_arrow_rounded,
                                          color: Colors.white, size: 20),
                                      SizedBox(width: 6),
                                      Text('Play All',
                                          style: TextStyle(color: Colors.white,
                                              fontWeight: FontWeight.w700, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: VibeBounce(
                                onTap: () => _shuffleAll(context, ref),
                                child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color:        theme.surface,
                                    borderRadius: BorderRadius.circular(21),
                                    border: Border.all(
                                        color: theme.accent.withAlpha(0x77)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.shuffle_rounded,
                                          color: theme.accentBright, size: 18),
                                      const SizedBox(width: 6),
                                      Text('Shuffle',
                                          style: TextStyle(color: theme.accentBright,
                                              fontWeight: FontWeight.w700, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Album grid ──────────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).padding.bottom + 100),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final g = albums[i];
                    return _AlbumCard(
                      group:        g,
                      theme:        theme,
                      onShowTracks: () => onShowTracks(g),
                      onPlayAlbum:  () => onPlayAlbum(g),
                      onDelete:     () => onDelete(g),
                    );
                  },
                  childCount: albums.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:   2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing:  12,
                  childAspectRatio: 0.76,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offline album track list sheet ────────────────────────────────────────────

class _OfflineAlbumSheet extends StatelessWidget {
  final List<Map<String, dynamic>> group; // already sorted by trackNumber
  final VibeTheme theme;
  final void Function(int startIndex) onPlay;

  const _OfflineAlbumSheet({
    required this.group,
    required this.theme,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final first  = group.first;
    final artUrl = first['artworkUrl'] as String? ?? '';
    final album  = first['album']      as String? ?? 'Unknown Album';
    final artist = first['artist']     as String? ?? '';
    final n      = group.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.45,
      maxChildSize:     0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color:        Color(0xFF0E0E18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color:        const Color(0xFF2E2E48),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Album header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: artUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: artUrl, width: 56, height: 56, fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(width: 56, height: 56, color: theme.surface),
                            errorWidget: (_, _, _) =>
                                Container(width: 56, height: 56, color: theme.surface,
                                    child: Icon(Icons.album, color: theme.textFaint)),
                          )
                        : Container(width: 56, height: 56, color: theme.surface,
                            child: Icon(Icons.album, color: theme.textFaint)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(album,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: theme.textColor, fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('$artist  ·  $n tracks',
                            style: TextStyle(color: theme.textFaint, fontSize: 12)),
                      ],
                    ),
                  ),
                  // Play All shortcut
                  GestureDetector(
                    onTap: () { Navigator.pop(context); onPlay(0); },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color:        theme.accent,
                        shape:        BoxShape.circle,
                        boxShadow: [BoxShadow(color: theme.accent.withAlpha(0x66), blurRadius: 10)],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.accent.withAlpha(0x22)),
            // Track list
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount:  group.length,
                itemBuilder: (_, i) {
                  final d       = group[i];
                  final title   = d['title']   as String? ?? '';
                  final dur     = Duration(microseconds: d['durationMicros'] as int? ?? 0);
                  final durStr  = dur == Duration.zero
                      ? ''
                      : '${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}';
                  final trackNo = d['trackNumber'] as int? ?? (i + 1);

                  return InkWell(
                    onTap: () { Navigator.pop(context); onPlay(i); },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('$trackNo',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: theme.textFaint, fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(title,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: theme.textColor, fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                          ),
                          if (durStr.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Text(durStr,
                                style: TextStyle(color: theme.textFaint, fontSize: 12)),
                          ],
                          const SizedBox(width: 8),
                          Icon(Icons.play_arrow_rounded, color: theme.accentBright, size: 18),
                        ],
                      ),
                    ),
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

// ── Playlists tab ─────────────────────────────────────────────────────────────

class _PlaylistsTab extends StatelessWidget {
  final List<Map<String, dynamic>> playlists;
  final VibeTheme   theme;
  final VoidCallback onCreate;
  final void Function(String) onPlay;
  final Future<void> Function(String, String) onRename;
  final Future<void> Function(String) onEditSongs;
  final Future<void> Function(String) onDelete;

  const _PlaylistsTab({
    required this.playlists,
    required this.theme,
    required this.onCreate,
    required this.onPlay,
    required this.onRename,
    required this.onEditSongs,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(
          top: 12, bottom: MediaQuery.of(context).padding.bottom + 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: VibeBounce(
            onTap: onCreate,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color:        theme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.accent.withAlpha(0x77)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: theme.accentBright, size: 20),
                  const SizedBox(width: 6),
                  Text('New Playlist',
                      style: TextStyle(color: theme.accentBright,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
        if (playlists.isEmpty)
          _EmptyState(
            icon:    Icons.queue_music_outlined,
            message: 'No offline playlists',
            sub:     'Create a playlist to organize your downloaded music',
            theme:   theme,
          )
        else
          for (final pl in playlists)
            _PlaylistRow(
              playlist:    pl,
              theme:       theme,
              onPlay:      () => onPlay(pl['id'] as String),
              onRename:    () => onRename(pl['id'] as String, pl['name'] as String? ?? ''),
              onEditSongs: () => onEditSongs(pl['id'] as String),
              onDelete:    () => onDelete(pl['id'] as String),
            ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final Map<String, dynamic> playlist;
  final VibeTheme   theme;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onEditSongs;
  final VoidCallback onDelete;

  const _PlaylistRow({
    required this.playlist,
    required this.theme,
    required this.onPlay,
    required this.onRename,
    required this.onEditSongs,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name  = playlist['name'] as String? ?? 'Playlist';
    final count = OfflinePlaylistService.trackCount(playlist['id'] as String);

    return VibeBounce(
      onTap: onPlay,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color:        theme.tint1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.accent.withAlpha(0x33)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color:        theme.accent.withAlpha(0x22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.accent.withAlpha(0x44)),
                ),
                child: Icon(Icons.queue_music_rounded, color: theme.accentBright, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.textColor, fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      count == 0 ? 'Empty — tap ··· to add songs' : '$count ${count == 1 ? 'song' : 'songs'}',
                      style: TextStyle(color: theme.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap:    onPlay,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.play_circle_outline, color: theme.accentBright, size: 24),
                ),
              ),
              GestureDetector(
                onTap: () => _showMenu(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.more_vert, color: theme.textFaint, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context:         context,
      backgroundColor: const Color(0xFF111119),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color:        const Color(0xFF2E2E48),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.library_add_outlined, color: Color(0xFFA855F7)),
              title:   const Text('Edit Songs', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); onEditSongs(); },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Color(0xFFA855F7)),
              title:   const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); onRename(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title:   const Text('Delete Playlist',
                  style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Song picker sheet ─────────────────────────────────────────────────────────

class _SongPickerSheet extends StatefulWidget {
  final String   playlistId;
  final List<Map<String, dynamic>> downloads;
  final VibeTheme theme;

  const _SongPickerSheet({
    required this.playlistId,
    required this.downloads,
    required this.theme,
  });

  @override
  State<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends State<_SongPickerSheet> {
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final pl = OfflinePlaylistService.getPlaylist(widget.playlistId);
    _selected.addAll(List<String>.from(pl?['trackIds'] as List? ?? []));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final pl      = OfflinePlaylistService.getPlaylist(widget.playlistId);
    final current = Set<String>.from(pl?['trackIds'] as List? ?? []);

    for (final id in _selected) {
      if (!current.contains(id)) {
        await OfflinePlaylistService.addTrack(widget.playlistId, id);
      }
    }
    for (final id in current) {
      if (!_selected.contains(id)) {
        await OfflinePlaylistService.removeTrack(widget.playlistId, id);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize:     0.5,
      maxChildSize:     0.94,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color:        Color(0xFF0E0E18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color:        const Color(0xFF2E2E48),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Songs',
                          style: TextStyle(color: theme.textColor, fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      Text(
                        _selected.isEmpty ? 'Tap to select' : '${_selected.length} selected',
                        style: TextStyle(color: theme.textFaint, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    style: TextButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            _selected.isEmpty ? 'Done' : 'Save  ${_selected.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.accent.withAlpha(0x22)),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount:  widget.downloads.length,
                itemBuilder: (_, i) {
                  final d      = widget.downloads[i];
                  final id     = d['itemId'] as String;
                  final sel    = _selected.contains(id);
                  final art    = d['artworkUrl'] as String? ?? '';
                  final title  = d['title']      as String? ?? '';
                  final artist = d['artist']     as String? ?? '';
                  final album  = d['album']      as String? ?? '';

                  return InkWell(
                    onTap: () => setState(() {
                      if (sel) { _selected.remove(id); } else { _selected.add(id); }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: art.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: art, width: 44, height: 44, fit: BoxFit.cover,
                                    placeholder: (_, _) =>
                                        Container(width: 44, height: 44, color: theme.surface),
                                    errorWidget: (_, _, _) =>
                                        Container(width: 44, height: 44, color: theme.surface,
                                            child: Icon(Icons.music_note,
                                                color: theme.textFaint, size: 18)),
                                  )
                                : Container(width: 44, height: 44, color: theme.surface,
                                    child: Icon(Icons.music_note, color: theme.textFaint, size: 18)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:      sel ? theme.accentBright : theme.textColor,
                                      fontSize:   14,
                                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                    )),
                                const SizedBox(height: 2),
                                Text(
                                  album.isNotEmpty ? '$artist  ·  $album' : artist,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: theme.textFaint, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:  sel ? theme.accent : Colors.transparent,
                              border: Border.all(
                                color: sel ? theme.accent : theme.textFaint.withAlpha(0x66),
                                width: 1.5,
                              ),
                            ),
                            child: sel
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : null,
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
      ),
    );
  }
}

// ── Floating download pill ────────────────────────────────────────────────────

class _DownloadPill extends StatelessWidget {
  final VibeTheme theme;
  const _DownloadPill({required this.theme});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: DownloadService.onChange,
      builder: (_, _) {
        if (!DownloadService.hasActiveDownloads) return const SizedBox.shrink();
        final ids  = DownloadService.activeItemIds;
        final n    = ids.length;
        final prog = n == 0
            ? 0.0
            : ids.fold(0.0, (s, id) => s + DownloadService.progress(id)) / n;
        final pct    = (prog * 100).toStringAsFixed(0);
        final bottom = MediaQuery.of(context).padding.bottom;
        return Positioned(
          bottom: bottom + 76,
          right:  16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color:        theme.accent,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(color: theme.accent.withAlpha(0x88), blurRadius: 14),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    value:           prog,
                    strokeWidth:     2,
                    color:           Colors.white,
                    backgroundColor: Colors.white.withAlpha(0x33),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$n ${n == 1 ? 'track' : 'tracks'}  ·  $pct%',
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Storage bar ───────────────────────────────────────────────────────────────

class _StorageBar extends StatelessWidget {
  final int    usedBytes;
  final String formattedSize;
  final VibeTheme theme;

  const _StorageBar({
    required this.usedBytes,
    required this.formattedSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const maxBytes = 10 * 1024 * 1024 * 1024; // 10 GB visual cap
    final fraction = (usedBytes / maxBytes).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value:           fraction,
              minHeight:       3,
              color:           theme.accent.withAlpha(0xBB),
              backgroundColor: theme.accent.withAlpha(0x1A),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(formattedSize,
            style: TextStyle(color: theme.textFaint, fontSize: 10)),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData  icon;
  final String    message;
  final String    sub;
  final VibeTheme theme;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: theme.textFaint),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textColor, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textFaint, fontSize: 13, height: 1.5)),
        ],
      ),
    ),
  );
}
