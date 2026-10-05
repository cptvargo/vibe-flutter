import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/jellyfin_api.dart';
import '../theme/vibe_theme.dart';
import 'create_playlist_sheet.dart';

class AddToPlaylistSheet extends StatefulWidget {
  final String    trackId;
  final VibeTheme theme;

  const AddToPlaylistSheet({
    super.key,
    required this.trackId,
    required this.theme,
  });

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;
  final Set<String> _adding = {};
  final Set<String> _added  = {};

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res   = await JellyfinApi.getPlaylists();
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _playlists = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(String playlistId) async {
    if (_added.contains(playlistId) || _adding.contains(playlistId)) return;
    setState(() => _adding.add(playlistId));
    try {
      await JellyfinApi.addToPlaylist(playlistId, [widget.trackId]);
      if (mounted) setState(() { _adding.remove(playlistId); _added.add(playlistId); });
    } catch (_) {
      if (mounted) setState(() => _adding.remove(playlistId));
    }
  }

  void _openNewPlaylist() {
    showModalBottomSheet<void>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => CreatePlaylistSheet(
        theme:     widget.theme,
        onCreated: (id) {
          _add(id);         // immediately add track to the new playlist
          _loadPlaylists(); // refresh list so it appears with a checkmark
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: const BoxDecoration(
          color:        Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        const Color(0xFF2E2E48),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Row(
                children: [
                  Text('Add to Playlist',
                      style: TextStyle(
                          color:      theme.textColor,
                          fontSize:   17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x15FFFFFF)),

            // New Playlist row
            _PlaylistRow(
              leading: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color:        const Color(0xFF1E1B4B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_rounded,
                    color: Color(0xFFA855F7), size: 26),
              ),
              title:    'New Playlist',
              subtitle: 'Create a new playlist',
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF5C5C78), size: 22),
              onTap: _openNewPlaylist,
            ),
            const Divider(height: 1, color: Color(0x0DFFFFFF)),

            // Playlist list
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child:   CircularProgressIndicator(color: Color(0xFFA855F7)),
              )
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                child: Text('No playlists yet — create one above',
                    style: TextStyle(color: theme.textFaint, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding:    const EdgeInsets.only(bottom: 12),
                  itemCount:  _playlists.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: Color(0x0DFFFFFF)),
                  itemBuilder: (_, i) {
                    final pl   = _playlists[i];
                    final id   = pl['Id']   as String? ?? '';
                    final name = pl['Name'] as String? ?? 'Playlist';
                    final count = pl['ChildCount'] as int? ?? 0;
                    final tag  = (pl['ImageTags'] as Map?)?['Primary'] as String?;
                    final art  = JellyfinApi.imageUrl(id, size: 96, tag: tag);

                    final isAdding = _adding.contains(id);
                    final isAdded  = _added.contains(id);

                    Widget trailing;
                    if (isAdding) {
                      trailing = const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFA855F7)),
                      );
                    } else if (isAdded) {
                      trailing = const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF4ADE80), size: 22);
                    } else {
                      trailing = Icon(Icons.add_circle_outline_rounded,
                          color: theme.textFaint, size: 22);
                    }

                    return _PlaylistRow(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: art,
                          width: 48, height: 48,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                              width: 48, height: 48,
                              color: const Color(0xFF1E1B4B)),
                          errorWidget: (_, _, _) => Container(
                            width: 48, height: 48,
                            color: const Color(0xFF1E1B4B),
                            child: const Icon(Icons.queue_music_rounded,
                                color: Color(0xFF5C5C78), size: 22),
                          ),
                        ),
                      ),
                      title:    name,
                      subtitle: '$count ${count == 1 ? 'song' : 'songs'}',
                      trailing: trailing,
                      onTap:    isAdded || isAdding ? null : () => _add(id),
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

class _PlaylistRow extends StatelessWidget {
  final Widget      leading;
  final String      title;
  final String      subtitle;
  final Widget      trailing;
  final VoidCallback? onTap;

  const _PlaylistRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color:    Color(0xFF7070A0),
                          fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}
