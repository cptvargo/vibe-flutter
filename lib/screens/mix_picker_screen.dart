import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../config/artist_images.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

class MixPickerScreen extends ConsumerStatefulWidget {
  final String type; // 'artist' or 'album'
  const MixPickerScreen({super.key, required this.type});

  bool get isArtist => type == 'artist';

  @override
  ConsumerState<MixPickerScreen> createState() => _MixPickerScreenState();
}

class _MixPickerScreenState extends ConsumerState<MixPickerScreen> {
  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  final TextEditingController _search  = TextEditingController();
  bool _loading = true;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = widget.isArtist
          ? await JellyfinApi.getArtists(limit: 200)
          : await JellyfinApi.getAlbums(limit: 200);
      var items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      // Deduplicate by name (Jellyfin can return the same artist twice)
      if (widget.isArtist) {
        final seen = <String>{};
        items = items.where((a) {
          final name = (a['Name'] as String? ?? '').trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        }).toList();
      }
      if (mounted) setState(() { _all = items; _filtered = items; _loading = false; });
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
  }

  Future<void> _playMix() async {
    if (_selected.isEmpty || _playing) return;
    if (!mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player'); // open instantly
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
      ref.read(audioHandlerProvider).playTracks(tracks);
    } catch (e) {
      debugPrint('MixPicker._playMix error: $e');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  String get _playLabel {
    if (_selected.isEmpty) {
      return widget.isArtist ? 'Pick an artist to start' : 'Pick an album to start';
    }
    final names = _selected.values.map((d) => d['Name'] as String? ?? '').toList();
    if (names.length == 1) return 'Play "${names[0]}" Mix';
    if (names.length == 2) return 'Play ${names[0]} + ${names[1]}';
    return 'Play ${names[0]}, ${names[1]} + ${names.length - 2} more';
  }

  @override
  Widget build(BuildContext context) {
    final theme  = ref.watch(themeProvider);
    final title  = widget.isArtist ? 'Artist Mix' : 'Album Mix';
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: theme.background,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(8, topPad + 8, 8, 8),
            color: theme.background,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_new,
                      color: theme.textColor, size: 20),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Selected preview + Play button ───────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: _selected.isEmpty ? 0 : 90,
            child: _selected.isEmpty
                ? const SizedBox.shrink()
                : _SelectedPreview(
                    selected: _selected,
                    theme: theme,
                    isArtist: widget.isArtist,
                    playing: _playing,
                    label: _playLabel,
                    onPlay: _playMix,
                    onRemove: (id) => setState(() => _selected.remove(id)),
                  ),
          ),

          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                hintText: widget.isArtist ? 'Search artists…' : 'Search albums…',
                hintStyle: TextStyle(color: theme.textFaint),
                prefixIcon: Icon(Icons.search, color: theme.textFaint),
                filled: true,
                fillColor: theme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const Divider(height: 1, color: Colors.white12),

          // ── Item list ────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: theme.accentBright))
                : _filtered.isEmpty
                    ? Center(
                        child: Text('No results',
                            style: TextStyle(color: theme.textFaint)),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final item       = _filtered[i];
                          final id         = item['Id'] as String? ?? '';
                          final name       = item['Name'] as String? ?? '';
                          final sub        = widget.isArtist
                              ? null
                              : item['AlbumArtist'] as String?;
                          final artUrl     = JellyfinApi.imageUrl(id, size: 200);
                          final localAsset = widget.isArtist ? kArtistImages[name] : null;
                          final isOn       = _selected.containsKey(id);

                          return ListTile(
                            onTap: () => _toggle(item),
                            leading: widget.isArtist
                                ? _Circle(url: artUrl, assetPath: localAsset,
                                    size: 44, theme: theme)
                                : _Square(url: artUrl, size: 44, theme: theme),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: isOn ? theme.accentBright : theme.textColor,
                                fontWeight: isOn ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            subtitle: sub != null
                                ? Text(sub,
                                    style: TextStyle(
                                        color: theme.textFaint, fontSize: 12))
                                : null,
                            trailing: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: isOn
                                  ? Icon(Icons.check_circle_rounded,
                                      key: const ValueKey(true),
                                      color: theme.accentBright, size: 22)
                                  : Icon(Icons.circle_outlined,
                                      key: const ValueKey(false),
                                      color: theme.textFaint, size: 22),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Selected preview bar ────────────────────────────────────────────────────
class _SelectedPreview extends StatelessWidget {
  final Map<String, Map<String, dynamic>> selected;
  final VibeTheme theme;
  final bool isArtist;
  final bool playing;
  final String label;
  final VoidCallback onPlay;
  final ValueChanged<String> onRemove;

  const _SelectedPreview({
    required this.selected,
    required this.theme,
    required this.isArtist,
    required this.playing,
    required this.label,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    const maxVisible = 5;
    final entries   = selected.entries.toList();
    final visible   = entries.take(maxVisible).toList();
    final overflow  = entries.length - maxVisible;

    return Container(
      color: theme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Item avatars
          ...visible.map((e) {
            final id         = e.key;
            final item       = e.value;
            final name       = item['Name'] as String? ?? '';
            final url        = JellyfinApi.imageUrl(id, size: 80);
            final localAsset = isArtist ? kArtistImages[name] : null;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onRemove(id),
                child: Stack(
                  children: [
                    isArtist
                        ? _Circle(url: url, assetPath: localAsset,
                            size: 36, theme: theme)
                        : _Square(url: url, size: 36, theme: theme),
                    // Small × badge
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: theme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 9, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Overflow dots
          if (overflow > 0) ...[
            const SizedBox(width: 2),
            Text(
              '+$overflow',
              style: TextStyle(
                color: theme.textFaint,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const Spacer(),

          // Play Mix button
          GestureDetector(
            onTap: onPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: playing
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shuffle_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Play Mix',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
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

// ── Shared image helpers ────────────────────────────────────────────────────
class _Circle extends StatelessWidget {
  final String url;
  final String? assetPath; // local asset takes priority when set
  final double size;
  final VibeTheme theme;
  const _Circle({required this.url, this.assetPath, required this.size, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (assetPath != null) {
      return ClipOval(
        child: Image.asset(assetPath!,
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size, height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
            width: size, height: size, color: theme.surface),
        errorWidget: (_, _, _) => Container(
            width: size, height: size, color: theme.surface,
            child: Icon(Icons.mic_none, color: theme.textFaint, size: size * 0.4)),
      ),
    );
  }
}

class _Square extends StatelessWidget {
  final String url;
  final double size;
  final VibeTheme theme;
  const _Square({required this.url, required this.size, required this.theme});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size, height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
            width: size, height: size, color: theme.surface),
        errorWidget: (_, _, _) => Container(
            width: size, height: size, color: theme.surface,
            child: Icon(Icons.album, color: theme.textFaint, size: size * 0.4)),
      ),
    );
  }
}
