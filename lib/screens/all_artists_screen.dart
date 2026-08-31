import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';
import '../widgets/artist_avatar.dart';

class AllArtistsScreen extends ConsumerStatefulWidget {
  const AllArtistsScreen({super.key});

  @override
  ConsumerState<AllArtistsScreen> createState() => _AllArtistsScreenState();
}

class _AllArtistsScreenState extends ConsumerState<AllArtistsScreen> {
  List<Map<String, dynamic>> _artists = [];
  bool _loading = true;
  String _query = '';
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        JellyfinApi.getArtists(limit: 500),
        JellyfinApi.getAIArtists(limit: 200),
      ]);
      if (!mounted) return;
      final seen = <String>{};
      final all = [
        ...((results[0]['Items'] as List?) ?? []).cast<Map<String, dynamic>>(),
        ...((results[1]['Items'] as List?) ?? []).cast<Map<String, dynamic>>(),
      ].where((a) {
        final name = (a['Name'] as String? ?? '').trim();
        if (name.isEmpty) return false;
        return seen.add(name.toLowerCase());
      }).toList()
        ..sort((a, b) => (a['Name'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['Name'] as String? ?? '').toLowerCase()));
      setState(() { _artists = all; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _artists;
    final q = _query.toLowerCase();
    return _artists.where((a) =>
        (a['Name'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  Map<String, List<Map<String, dynamic>>> get _grouped {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final a in _filtered) {
      final name = (a['Name'] as String? ?? '');
      final key  = name.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(name[0])
          ? name[0].toUpperCase()
          : '#';
      (result[key] ??= []).add(a);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme   = ref.watch(themeProvider);
    final groups  = _grouped;
    final letters = groups.keys.toList()
      ..sort((a, b) => a == '#' ? 1 : b == '#' ? -1 : a.compareTo(b));

    return Scaffold(
      backgroundColor: const Color(0xFF06060F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR LIBRARY',
                          style: TextStyle(
                            color: Colors.white.withAlpha(0x4D),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'All Artists',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: theme.accent.withAlpha(0xAA),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                            if (!_loading && _artists.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: theme.accent.withAlpha(0x22),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_artists.length}',
                                  style: TextStyle(
                                    color: theme.accentBright,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: Colors.white.withAlpha(0x99), size: 22),
                    onPressed: () => context.pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(0x14),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Search bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(0x0F),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(0x0F)),
                ),
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Search artists…',
                    hintStyle:
                        TextStyle(color: Colors.white.withAlpha(0x4D)),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.white.withAlpha(0x4D), size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: Colors.white.withAlpha(0x66), size: 18),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Results count (search mode only) ────────────────────────
            if (!_loading && _query.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  '${_filtered.length} ${_filtered.length == 1 ? 'artist' : 'artists'}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(0x33),
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

            // ── List ─────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No artists found',
                            style: TextStyle(
                                color: Colors.white.withAlpha(0x44),
                                fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 24,
                          ),
                          itemCount: letters.fold<int>(
                              0, (sum, l) => sum + 1 + (groups[l]?.length ?? 0)),
                          itemBuilder: (context, index) {
                            int offset = 0;
                            for (final letter in letters) {
                              final items = groups[letter]!;
                              if (index == offset) {
                                return _LetterHeader(
                                  letter: letter,
                                  count: items.length,
                                  theme: theme,
                                );
                              }
                              offset++;
                              if (index < offset + items.length) {
                                final artist = items[index - offset];
                                return _ArtistRow(
                                  artist: artist,
                                  theme: theme,
                                  isLast: index - offset == items.length - 1,
                                  onTap: (a) => context.push(
                                    '/artist/${a['Id']}'
                                    '?name=${Uri.encodeComponent(a['Name'] as String? ?? '')}',
                                  ),
                                );
                              }
                              offset += items.length;
                            }
                            return const SizedBox.shrink();
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterHeader extends StatelessWidget {
  final String letter;
  final int count;
  final VibeTheme theme;
  const _LetterHeader({
    required this.letter,
    required this.count,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          letter,
          style: TextStyle(
            color: theme.accent.withAlpha(0xBB),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withAlpha(0x28),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 1,
            width: 40,
            color: Colors.white.withAlpha(0x0D),
          ),
        ),
      ],
    ),
  );
}

class _ArtistRow extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VibeTheme theme;
  final bool isLast;
  final void Function(Map<String, dynamic>) onTap;

  const _ArtistRow({
    required this.artist,
    required this.theme,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final id       = artist['Id']   as String? ?? '';
    final name     = artist['Name'] as String? ?? '';
    final imageTag = (artist['ImageTags'] as Map?)?['Primary'] as String?;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(artist),
        splashColor: theme.accent.withAlpha(0x18),
        highlightColor: Colors.white.withAlpha(0x07),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: isLast
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withAlpha(0x0A),
                    ),
                  ),
                ),
          child: Row(
            children: [
              // Avatar with subtle accent glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.accent.withAlpha(0x2E),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ArtistAvatar(
                  id: id,
                  name: name,
                  size: 62,
                  theme: theme,
                  imageTag: imageTag,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withAlpha(0x44), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
