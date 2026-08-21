import 'dart:async';
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
  int    _tab          = 0;
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

  // Groups flat download list by albumId. Each group is sorted by
  // disc + track number using stored Jellyfin metadata.
  List<List<Map<String, dynamic>>> get _albums {
    final map   = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final d in _downloads) {
      final key = (d['albumId'] as String?) ?? (d['itemId'] as String);
      if (!map.containsKey(key)) order.add(key);
      map.putIfAbsent(key, () => []).add(d);
    }
    return order.map((k) => _byDiscTrack(map[k]!)).toList();
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
    // Merge all groups in order, each group already sorted by trackNumber
    final tracks = _albums.expand((g) => g).map(DownloadService.trackFromData).toList();
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

    final subtitle = _downloads.isEmpty
        ? 'No downloads yet'
        : _calcStorage
            ? '${albums.length} ${albums.length == 1 ? 'album' : 'albums'} · …'
            : '${albums.length} ${albums.length == 1 ? 'album' : 'albums'} · ${_fmt(_storageBytes)}';

    return ColoredBox(
      color: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offline Hub',
                      style: TextStyle(
                        color: theme.textColor, fontSize: 26,
                        fontWeight: FontWeight.w800, letterSpacing: 0.2,
                        shadows: [
                          Shadow(color: theme.accent.withAlpha(0xAA), blurRadius: 12),
                        ],
                      )),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: theme.textFaint, fontSize: 12)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                _Chip(label: 'Albums',    count: albums.length,     active: _tab == 0,
                    theme: theme, onTap: () => setState(() => _tab = 0)),
                const SizedBox(width: 10),
                _Chip(label: 'Playlists', count: _playlists.length, active: _tab == 1,
                    theme: theme, onTap: () => setState(() => _tab = 1)),
              ]),
            ),

            Expanded(
              child: _tab == 0
                  ? _AlbumsTab(
                      albums:         albums,
                      theme:          theme,
                      onPlayAll:      _playAll,
                      onShowTracks:   _showAlbumTracks,
                      onPlayAlbum:    (g) => _playAlbumGroup(g),
                      onDelete:       _deleteAlbumGroup,
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
  final void Function(List<Map<String, dynamic>>) onShowTracks;
  final void Function(List<Map<String, dynamic>>) onPlayAlbum;
  final Future<void> Function(List<Map<String, dynamic>>) onDelete;

  const _AlbumsTab({
    required this.albums,
    required this.theme,
    required this.onPlayAll,
    required this.onShowTracks,
    required this.onPlayAlbum,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasActive = DownloadService.hasActiveDownloads;
    if (albums.isEmpty && !hasActive) {
      return _EmptyState(
        icon:    Icons.album_outlined,
        message: 'No downloaded albums',
        sub:     'Open any album and tap ↓ to save it for offline listening',
        theme:   theme,
      );
    }
    return ListView(
      padding: EdgeInsets.only(
          top: 12, bottom: MediaQuery.of(context).padding.bottom + 100),
      children: [
        if (albums.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: VibeBounce(
              onTap: onPlayAll,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color:        theme.accent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: theme.accent.withAlpha(0x55), blurRadius: 14)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'Play All  (${albums.fold(0, (n, g) => n + g.length)} tracks)',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (hasActive) _ActiveBanner(theme: theme),

        for (final group in albums)
          _AlbumRow(
            group:        group,
            theme:        theme,
            onShowTracks: () => onShowTracks(group),
            onPlayAlbum:  () => onPlayAlbum(group),
            onDelete:     () => onDelete(group),
          ),
      ],
    );
  }
}

class _AlbumRow extends StatelessWidget {
  final List<Map<String, dynamic>> group;
  final VibeTheme   theme;
  final VoidCallback onShowTracks;
  final VoidCallback onPlayAlbum;
  final VoidCallback onDelete;

  const _AlbumRow({
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
      onTap: onShowTracks, // tap card → track list, not immediate play
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color:        theme.tint1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.accent.withAlpha(0x28)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl, width: 56, height: 56, fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(width: 56, height: 56, color: theme.surface),
                        errorWidget: (_, _, _) =>
                            Container(width: 56, height: 56, color: theme.surface,
                                child: Icon(Icons.album, color: theme.textFaint, size: 26)),
                      )
                    : Container(width: 56, height: 56, color: theme.surface,
                        child: Icon(Icons.album, color: theme.textFaint, size: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.textColor, fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('$artist  ·  $n ${n == 1 ? 'track' : 'tracks'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.textDim, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.offline_pin, color: theme.accentBright.withAlpha(0x88), size: 16),
              const SizedBox(width: 2),
              GestureDetector(
                onTap:    onPlayAlbum,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(Icons.play_circle_outline, color: theme.accentBright, size: 24),
                ),
              ),
              GestureDetector(
                onTap:    onDelete,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(Icons.delete_outline, color: theme.textFaint, size: 20),
                ),
              ),
            ],
          ),
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

// ── Active download banner ────────────────────────────────────────────────────

class _ActiveBanner extends StatelessWidget {
  final VibeTheme theme;
  const _ActiveBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    final ids     = DownloadService.activeItemIds;
    final count   = ids.length;
    final avgProg = count == 0
        ? 0.0
        : ids.fold(0.0, (s, id) => s + DownloadService.progress(id)) / count;
    final pct   = (avgProg * 100).toStringAsFixed(0);
    final info  = count == 1 ? DownloadService.activeInfo(ids.first) : null;
    final label = info != null
        ? '${info.$1}  —  $pct%'
        : '$count ${count == 1 ? 'track' : 'tracks'} downloading…  $pct%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color:        theme.accent.withAlpha(0x22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.accent.withAlpha(0x44)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textColor, fontSize: 12)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value:           avgProg,
                minHeight:       4,
                color:           theme.accentBright,
                backgroundColor: theme.accentBright.withAlpha(0x22),
              ),
            ),
          ],
        ),
      ),
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
