import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../widgets/artist_avatar.dart';
import '../theme/vibe_theme.dart';

class MixPickerScreen extends ConsumerStatefulWidget {
  final String type; // 'artist' or 'album'
  const MixPickerScreen({super.key, required this.type});

  bool get isArtist => type == 'artist';

  @override
  ConsumerState<MixPickerScreen> createState() => _MixPickerScreenState();
}

class _MixPickerScreenState extends ConsumerState<MixPickerScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  final TextEditingController _search  = TextEditingController();
  final ScrollController _scrollCtrl  = ScrollController();
  bool _loading = true;
  bool _playing = false;

  late final AnimationController _barCtrl;
  late final Animation<double>    _barAnim;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic);
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    _search.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (widget.isArtist) {
        final results = await Future.wait([
          JellyfinApi.getArtists(limit: 500),
          JellyfinApi.getAIArtists(limit: 200),
        ]);
        final seen = <String>{};
        final items = [
          ...((results[0]['Items'] as List?) ?? []).cast<Map<String, dynamic>>(),
          ...((results[1]['Items'] as List?) ?? []).cast<Map<String, dynamic>>(),
        ].where((a) {
          final name = (a['Name'] as String? ?? '').trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        }).toList()
          ..sort((a, b) => (a['Name'] as String? ?? '')
              .toLowerCase()
              .compareTo((b['Name'] as String? ?? '').toLowerCase()));
        if (mounted) setState(() { _all = items; _filtered = items; _loading = false; });
      } else {
        final res = await JellyfinApi.getAlbums(limit: 500);
        final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
        if (mounted) setState(() { _all = items; _filtered = items; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((item) =>
              (item['Name'] as String? ?? '').toLowerCase().contains(q)).toList();
    });
  }

  void _toggle(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = item;
      }
    });
    if (_selected.isNotEmpty) {
      _barCtrl.forward();
    } else {
      _barCtrl.reverse();
    }
  }

  Future<void> _playMix() async {
    if (_selected.isEmpty || _playing) return;
    if (!mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    setState(() => _playing = true);
    try {
      final futures = _selected.keys.map((id) async {
        final res = widget.isArtist
            ? await JellyfinApi.getArtistAllTracks(id)
            : await JellyfinApi.getAlbumTracks(id);
        return ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
      final results = await Future.wait(futures);
      final tracks = results.expand((l) => l).map(VibeTrack.fromJellyfin).toList()..shuffle();
      if (tracks.isEmpty) return;
      ref.read(audioHandlerProvider).playTracks(tracks, playbackContext: 'station');
    } catch (e) {
      debugPrint('MixPicker._playMix error: $e');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  String get _countLabel {
    final n = _selected.length;
    if (widget.isArtist) return n == 1 ? '1 artist selected' : '$n artists selected';
    return n == 1 ? '1 album selected' : '$n albums selected';
  }

  @override
  Widget build(BuildContext context) {
    final theme  = ref.watch(themeProvider);
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    final title    = widget.isArtist ? 'Artist Mix' : 'Album Mix';
    final subtitle = widget.isArtist
        ? 'Pick artists to build your mix'
        : 'Pick albums to build your mix';

    return Scaffold(
      backgroundColor: const Color(0xFF06060F),
      body: Stack(
        children: [
          // ── Ambient glow ──────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.6),
                  radius: 1.2,
                  colors: [
                    theme.accent.withAlpha(0x22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(8, topPad + 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white.withAlpha(0xCC), size: 20),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              shadows: [
                                Shadow(
                                  color: theme.accent.withAlpha(0xAA),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withAlpha(0x66),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Search bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(0x0D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withAlpha(0x12), width: 1),
                  ),
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: widget.isArtist
                          ? 'Search artists…'
                          : 'Search albums…',
                      hintStyle: TextStyle(
                          color: Colors.white.withAlpha(0x40), fontSize: 15),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Colors.white.withAlpha(0x40), size: 20),
                      suffixIcon: _search.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded,
                                  color: Colors.white.withAlpha(0x55), size: 18),
                              onPressed: () {
                                _search.clear();
                                _filter();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Count label ───────────────────────────────────────────────
              if (!_loading)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${_filtered.length} ${widget.isArtist ? 'artists' : 'albums'}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(0x33),
                          fontSize: 12,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Grid ──────────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: theme.accentBright, strokeWidth: 2))
                    : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No results',
                              style: TextStyle(
                                  color: Colors.white.withAlpha(0x44),
                                  fontSize: 15),
                            ),
                          )
                        : GridView.builder(
                            controller: _scrollCtrl,
                            padding: EdgeInsets.fromLTRB(
                                16, 8, 16,
                                botPad + (_selected.isNotEmpty ? 110 : 32)),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: widget.isArtist ? 3 : 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 16,
                              childAspectRatio:
                                  widget.isArtist ? 0.75 : 0.72,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final item = _filtered[i];
                              final id   = item['Id'] as String? ?? '';
                              final isOn = _selected.containsKey(id);
                              return widget.isArtist
                                  ? _ArtistCard(
                                      item: item,
                                      theme: theme,
                                      selected: isOn,
                                      onTap: () => _toggle(item),
                                    )
                                  : _AlbumCard(
                                      item: item,
                                      theme: theme,
                                      selected: isOn,
                                      onTap: () => _toggle(item),
                                    );
                            },
                          ),
              ),
            ],
          ),

          // ── Floating play bar ──────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SizeTransition(
              sizeFactor: _barAnim,
              axisAlignment: -1,
              child: _PlayBar(
                label: _countLabel,
                playing: _playing,
                theme: theme,
                botPad: botPad,
                onPlay: _playMix,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artist card ─────────────────────────────────────────────────────────────
class _ArtistCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.item,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id   = item['Id']   as String? ?? '';
    final name = item['Name'] as String? ?? '';
    final tag  = (item['ImageTags'] as Map?)?['Primary'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with selection ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.all(selected ? 3 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected
                  ? LinearGradient(
                      colors: [theme.accent, theme.accentBright],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: theme.accent.withAlpha(0x55),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                ArtistAvatar(
                  id: id,
                  name: name,
                  size: 80,
                  theme: theme,
                  imageTag: tag,
                ),
                if (selected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.accent.withAlpha(0x44),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? theme.accentBright : Colors.white.withAlpha(0xCC),
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Album card ──────────────────────────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.item,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id     = item['Id']          as String? ?? '';
    final name   = item['Name']        as String? ?? '';
    final artist = item['AlbumArtist'] as String? ?? '';
    final tag    = (item['ImageTags'] as Map?)?['Primary'] as String?;
    final artUrl = JellyfinApi.imageUrl(id, size: 300, tag: tag);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Art with selection ring
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.all(selected ? 3 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(selected ? 11 : 8),
              gradient: selected
                  ? LinearGradient(
                      colors: [theme.accent, theme.accentBright],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: theme.accent.withAlpha(0x55),
                        blurRadius: 16,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(selected ? 8 : 8),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CachedNetworkImage(
                      imageUrl: artUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: theme.surface),
                      errorWidget: (_, _, _) => Container(
                        color: theme.surface,
                        child: Icon(Icons.album,
                            color: theme.textFaint, size: 32),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned.fill(
                      child: Container(
                        color: theme.accent.withAlpha(0x55),
                        child: const Center(
                          child: Icon(Icons.check_rounded,
                              color: Colors.white, size: 32),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? theme.accentBright
                  : Colors.white.withAlpha(0xCC),
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (artist.isNotEmpty)
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withAlpha(0x44),
                  fontSize: 10,
                  height: 1.3),
            ),
        ],
      ),
    );
  }
}

// ── Floating play bar ────────────────────────────────────────────────────────
class _PlayBar extends StatelessWidget {
  final String label;
  final bool playing;
  final VibeTheme theme;
  final double botPad;
  final VoidCallback onPlay;

  const _PlayBar({
    required this.label,
    required this.playing,
    required this.theme,
    required this.botPad,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, botPad + 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C1C),
        border: Border(
            top: BorderSide(color: Colors.white.withAlpha(0x12), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(0x99),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(0x88),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onPlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.accent, theme.accentBright],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withAlpha(0x66),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: playing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shuffle_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Play Mix',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
