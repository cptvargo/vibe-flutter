import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../services/preset_mix_service.dart';
import '../theme/vibe_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/vibe_ui.dart';

/// Full-screen detail view for either a Fire Mix or a Preset Mix.
///
/// [mixId] is null for Fire Mix (non-renameable).
class MixDetailScreen extends ConsumerStatefulWidget {
  final String        name;
  final List<VibeTrack> tracks;
  final String?       mixId;

  const MixDetailScreen({
    super.key,
    required this.name,
    required this.tracks,
    this.mixId,
  });

  @override
  ConsumerState<MixDetailScreen> createState() => _MixDetailScreenState();
}

class _MixDetailScreenState extends ConsumerState<MixDetailScreen> {
  late String _name;
  String? _selectedGenre; // null = All

  @override
  void initState() {
    super.initState();
    _name = widget.name;
  }

  bool get _isFire => widget.mixId == null;

  List<String> get _genres {
    final seen = <String>{};
    final out  = <String>[];
    for (final t in widget.tracks) {
      for (final g in t.genres) {
        if (g.isNotEmpty && seen.add(g)) out.add(g);
      }
    }
    out.sort();
    return out;
  }

  List<VibeTrack> get _filteredTracks {
    if (_selectedGenre == null) return widget.tracks;
    return widget.tracks.where((t) => t.genres.contains(_selectedGenre)).toList();
  }

  // ── Playback ─────────────────────────────────────────────────────────────────

  void _play({required bool shuffle}) {
    final filtered = _filteredTracks;
    if (filtered.isEmpty) return;
    final handler = ref.read(audioHandlerProvider);
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    final tracks = shuffle ? ([...filtered]..shuffle()) : filtered;
    handler.playTracks(tracks, playbackContext: 'mix');
    context.push('/player');
  }

  void _playTrack(int index) {
    final filtered = _filteredTracks;
    if (filtered.isEmpty) return;
    final handler = ref.read(audioHandlerProvider);
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    handler.playTracks(filtered, startIndex: index, playbackContext: 'mix');
    context.push('/player');
  }

  // ── Rename ────────────────────────────────────────────────────────────────────

  Future<void> _rename() async {
    if (widget.mixId == null) return;
    final ctrl = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2A),
        title: const Text('Rename Mix',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF9F67F0)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFCB9AFF), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF9F67F0))),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != _name) {
      await PresetMixService.rename(widget.mixId!, result);
      if (mounted) setState(() => _name = result);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(playerThemeProvider);
    final collage = widget.tracks
        .map((t) => t.artworkUrl)
        .toSet()
        .take(4)
        .toList();
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(theme, collage, screenW)),
              SliverToBoxAdapter(child: _buttons(theme)),
              if (_isFire && _genres.isNotEmpty)
                SliverToBoxAdapter(child: _genreChips(theme)),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final filtered = _filteredTracks;
                    return _TrackRow(
                      track:   filtered[i],
                      index:   i,
                      theme:   theme,
                      isFire:  _isFire,
                      onTap:   () => _playTrack(i),
                    );
                  },
                  childCount: _filteredTracks.length,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 88,
                ),
              ),
            ],
          ),

          // Floating back button
          Positioned(
            top:  MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _FloatingBack(theme: theme),
          ),

          // Mini player
          const Positioned(
            left: 0, right: 0, bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }

  Widget _header(VibeTheme theme, List<String> collage, double screenW) {
    final collageSize = screenW;
    return SizedBox(
      height: collageSize + 120,
      child: Stack(
        children: [
          // 2×2 art collage — full width
          SizedBox(
            width:  collageSize,
            height: collageSize,
            child: ArtCollage(imageUrls: collage, theme: theme),
          ),

          // Gradient from the bottom of the collage into the screen background
          Positioned(
            left: 0, right: 0,
            top:  collageSize - 80,
            height: 160,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.topCenter,
                  end:    Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0D0D14),
                  ],
                ),
              ),
            ),
          ),

          // Mix name + track count
          Positioned(
            left: 20, right: 20,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fire icon for fire mix
                if (_isFire)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.whatshot_rounded,
                            color: Color(0xFFFF6B1A), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'FIRE MIX',
                          style: TextStyle(
                            color:         const Color(0xFFFF6B1A),
                            fontSize:      11,
                            fontWeight:    FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Mix name (tappable to rename for preset mixes)
                GestureDetector(
                  onTap: widget.mixId != null ? _rename : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _name,
                          style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   26,
                            fontWeight: FontWeight.w800,
                            height:     1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.mixId != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_rounded,
                            color: Colors.white38, size: 16),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 4),
                Text(
                  _selectedGenre == null
                      ? '${widget.tracks.length} tracks'
                      : '${_filteredTracks.length} of ${widget.tracks.length} tracks',
                  style: const TextStyle(
                    color:    Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _genreChips(VibeTheme theme) {
    final genres = _genres;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection:  Axis.horizontal,
        padding:          const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _GenreChip(
            label:    'All',
            selected: _selectedGenre == null,
            accent:   theme.accent,
            onTap:    () => setState(() => _selectedGenre = null),
          ),
          ...genres.map((g) => Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _GenreChip(
              label:    g,
              selected: _selectedGenre == g,
              accent:   theme.accent,
              onTap:    () => setState(() =>
                  _selectedGenre = _selectedGenre == g ? null : g),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buttons(VibeTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: VibeBounce(
              onTap: () => _play(shuffle: false),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color:        theme.accent,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(color: theme.accent.withAlpha(0x66), blurRadius: 16),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 6),
                    Text('Play',
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
          Expanded(
            child: VibeBounce(
              onTap: () => _play(shuffle: true),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color:        Colors.white.withAlpha(0x14),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.accentBright.withAlpha(0x66),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shuffle_rounded,
                        color: theme.accentBright, size: 20),
                    const SizedBox(width: 6),
                    Text('Shuffle',
                      style: TextStyle(
                        color:      theme.accentBright,
                        fontWeight: FontWeight.w700,
                        fontSize:   15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Track row ─────────────────────────────────────────────────────────────────

class _TrackRow extends StatelessWidget {
  final VibeTrack  track;
  final int        index;
  final VibeTheme  theme;
  final bool       isFire;
  final VoidCallback onTap;

  const _TrackRow({
    required this.track,
    required this.index,
    required this.theme,
    required this.isFire,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl:    track.artworkUrl,
                width:       46,
                height:      46,
                fit:         BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 46, height: 46, color: theme.surface,
                  child: Icon(Icons.music_note, color: theme.textFaint, size: 20),
                ),
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
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: TextStyle(
                      color:    Colors.white.withAlpha(0x77),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Fire icon for fire mix
            if (isFire)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.whatshot_rounded,
                    color: const Color(0xFFFF6B1A).withAlpha(0xBB), size: 16),
              ),

            // Duration
            const SizedBox(width: 8),
            Text(
              _fmt(track.duration),
              style: TextStyle(
                color:    Colors.white.withAlpha(0x55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── Genre chip ────────────────────────────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String     label;
  final bool       selected;
  final Color      accent;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve:    Curves.easeOut,
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:        selected ? accent : Colors.white.withAlpha(0x14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.white.withAlpha(0x22),
          ),
          boxShadow: selected
              ? [BoxShadow(color: accent.withAlpha(0x55), blurRadius: 8)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color:      selected ? Colors.white : Colors.white60,
            fontSize:   13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Floating back button ──────────────────────────────────────────────────────

class _FloatingBack extends StatelessWidget {
  final VibeTheme theme;
  const _FloatingBack({required this.theme});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      width:  40,
      height: 40,
      decoration: BoxDecoration(
        color:        Colors.black.withAlpha(0x88),
        shape:        BoxShape.circle,
        border: Border.all(color: Colors.white12),
      ),
      child: const Icon(Icons.arrow_back_ios_new_rounded,
          color: Colors.white, size: 16),
    ),
  );
}
