import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

// Layout constants — kept consistent between render and offset math
const _kColumns     = 3;
const _kHPad        = 16.0;
const _kGap         = 10.0;
const _kMainSpacing = 14.0;
const _kScrubberW   = 22.0;
const _kScrubberPad = 6.0;
const _kExtraH      = 50.0;  // text area under album art
const _kHeaderH     = 36.0;  // letter header row height

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<Map<String, dynamic>> _albums = [];
  bool _loading = true;
  final _scrollCtrl = ScrollController();
  String? _activeLetter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await JellyfinApi.getAlbums(limit: 1000);
      final items = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() { _albums = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _letterFor(Map<String, dynamic> album) {
    final name = ((album['SortName'] as String?)?.trim()
            ?? (album['Name'] as String?)?.trim()
            ?? '').toUpperCase();
    if (name.isEmpty) return '#';
    final ch = name[0];
    return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
  }

  void _scrollTo(String letter, Map<String, double> offsets) {
    final target = offsets[letter];
    if (target == null || !_scrollCtrl.hasClients) return;
    final clamped = math.min(target, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(clamped,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final screenW = MediaQuery.of(context).size.width;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.accentBright));
    }

    // Group by letter
    final groups  = <String, List<Map<String, dynamic>>>{};
    for (final album in _albums) {
      final letter = _letterFor(album);
      (groups[letter] ??= []).add(album);
    }
    final letters = [...groups.keys]
      ..sort((a, b) => a == '#' ? 1 : b == '#' ? -1 : a.compareTo(b));

    // Cell geometry — must match SliverGrid layout exactly
    final availW  = screenW - _kHPad * 2 - _kScrubberW - _kScrubberPad
                    - _kGap * (_kColumns - 1);
    final cardW   = availW / _kColumns;
    final cellH   = cardW + _kExtraH;
    final rowH    = cellH + _kMainSpacing;

    // Pre-compute cumulative scroll offset per letter
    final offsets = <String, double>{};
    var cumulative = 0.0;
    for (final letter in letters) {
      offsets[letter] = cumulative;
      final numRows   = (groups[letter]!.length / _kColumns).ceil();
      cumulative += _kHeaderH + numRows * rowH;
    }

    return Stack(
      children: [
        // ── Album grid ─────────────────────────────────────────────────────
        CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            for (final letter in letters) ...[
              // Letter section header
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _kHeaderH,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        _kHPad, 10, _kHPad + _kScrubberW + _kScrubberPad, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          letter,
                          style: TextStyle(
                            color: theme.accentBright,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 0.5,
                            color: theme.accentBright.withAlpha(0x2A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Album grid for this letter
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    _kHPad, 0,
                    _kHPad + _kScrubberW + _kScrubberPad,
                    _kMainSpacing),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _AlbumCell(
                      album: groups[letter]![i],
                      cardW: cardW,
                      theme: theme,
                      onTap: () {
                        final a      = groups[letter]![i];
                        final id     = a['Id'] as String? ?? '';
                        final name   = Uri.encodeComponent(a['Name']        as String? ?? '');
                        final artist = Uri.encodeComponent(a['AlbumArtist'] as String? ?? '');
                        final year   = a['ProductionYear'] as int?;
                        final yParam = year != null ? '&year=$year' : '';
                        context.push('/album/$id?name=$name&artist=$artist$yParam');
                      },
                    ),
                    childCount: groups[letter]!.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:  _kColumns,
                    crossAxisSpacing: _kGap,
                    mainAxisSpacing:  _kMainSpacing,
                    childAspectRatio: cardW / cellH,
                  ),
                ),
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
          ],
        ),

        // ── A-Z scrubber ───────────────────────────────────────────────────
        Positioned(
          right: 0,
          top: 0,
          bottom: 100,
          width: _kScrubberW + _kScrubberPad,
          child: _Scrubber(
            letters: letters,
            activeLetter: _activeLetter,
            theme: theme,
            onLetter: (l) {
              if (l == _activeLetter) return;
              setState(() => _activeLetter = l);
              _scrollTo(l, offsets);
            },
            onEnd: () => setState(() => _activeLetter = null),
          ),
        ),

        // ── Floating letter bubble while scrubbing ─────────────────────────
        if (_activeLetter != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    color: theme.accent.withAlpha(0xE0),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accent.withAlpha(0x55),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _activeLetter!,
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Album cell ──────────────────────────────────────────────────────────────
class _AlbumCell extends StatelessWidget {
  final Map<String, dynamic> album;
  final double cardW;
  final VibeTheme theme;
  final VoidCallback onTap;

  const _AlbumCell({
    required this.album,
    required this.cardW,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id     = album['Id']           as String? ?? '';
    final name   = album['Name']         as String? ?? '';
    final artist = album['AlbumArtist']  as String?
        ?? (album['Artists'] as List?)?.firstOrNull as String? ?? '';
    final artUrl = JellyfinApi.imageUrl(id, size: 300);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: artUrl,
              width: cardW, height: cardW,
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  Container(width: cardW, height: cardW, color: theme.surface),
              errorWidget: (_, _, _) =>
                  Container(width: cardW, height: cardW, color: theme.surface),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textDim, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }
}

// ── A-Z scrubber strip ──────────────────────────────────────────────────────
class _Scrubber extends StatelessWidget {
  final List<String> letters;
  final String? activeLetter;
  final VibeTheme theme;
  final ValueChanged<String> onLetter;
  final VoidCallback onEnd;

  const _Scrubber({
    required this.letters,
    required this.activeLetter,
    required this.theme,
    required this.onLetter,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final totalH  = constraints.maxHeight;
        final perItem = totalH / letters.length;

        void handle(Offset local) {
          final idx = (local.dy / perItem).floor().clamp(0, letters.length - 1);
          onLetter(letters[idx]);
        }

        return GestureDetector(
          onTapDown:           (d) => handle(d.localPosition),
          onTapUp:             (_) => onEnd(),
          onVerticalDragUpdate: (d) => handle(d.localPosition),
          onVerticalDragEnd:   (_) => onEnd(),
          child: Container(
            color: Colors.transparent,
            padding: EdgeInsets.only(right: _kScrubberPad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: letters.map((l) {
                final active = l == activeLetter;
                return AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 100),
                  style: TextStyle(
                    color: active ? theme.accentBright : theme.textFaint,
                    fontSize: active ? 12 : 9,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w400,
                    fontFamily: 'RobotoMono',
                  ),
                  child: Text(l),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
