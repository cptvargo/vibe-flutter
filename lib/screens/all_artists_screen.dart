import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/vibe_ui.dart';

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

  // Group A-Z
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
    final theme  = ref.watch(themeProvider);
    final groups = _grouped;
    final letters = groups.keys.toList()
      ..sort((a, b) => a == '#' ? 1 : b == '#' ? -1 : a.compareTo(b));

    return Scaffold(
      backgroundColor: const Color(0xFF06060F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
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
                        Text(
                          'All Artists',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            shadows: [
                              Shadow(color: theme.accent.withAlpha(0xAA), blurRadius: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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

            // Search bar
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
                    hintStyle: TextStyle(color: Colors.white.withAlpha(0x4D)),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),

            const SizedBox(height: 8),

            if (!_loading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '${_filtered.length} ${_filtered.length == 1 ? 'artist' : 'artists'}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(0x33),
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Text('No artists found',
                            style: TextStyle(
                                color: Colors.white.withAlpha(0x44), fontSize: 15)),
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
                                return _LetterHeader(letter: letter);
                              }
                              offset++;
                              if (index < offset + items.length) {
                                return _ArtistRow(
                                  artist: items[index - offset],
                                  theme: theme,
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
  const _LetterHeader({required this.letter});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(
      letter,
      style: TextStyle(
        color: Colors.white.withAlpha(0x33),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );
}

class _ArtistRow extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VibeTheme theme;
  final void Function(Map<String, dynamic>) onTap;
  const _ArtistRow({required this.artist, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id   = artist['Id']   as String? ?? '';
    final name = artist['Name'] as String? ?? '';

    return InkWell(
      onTap: () => onTap(artist),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            ArtistAvatar(id: id, name: name, size: 52, theme: theme,
                imageTag: (artist['ImageTags'] as Map?)?['Primary'] as String?),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withAlpha(0x33), size: 18),
          ],
        ),
      ),
    );
  }
}
