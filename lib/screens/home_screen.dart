import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../services/recently_played_service.dart';
import '../theme/vibe_theme.dart';
import '../widgets/vibe_ui.dart';

const _kAlbumSize  = 140.0;
const _kArtistSize = 80.0;

const _kStations = <VibeStation>[
  (id: 'fire_mix',   label: 'Fire Mix',       icon: Icons.whatshot,    sub: 'Your marked bangers'),
  (id: 'vibe_radio', label: 'ViBE Radio',     icon: Icons.radio,       sub: 'Your full library'),
  (id: 'artist_mix', label: 'Artist Mix',     icon: Icons.mic_none,    sub: 'Based on now playing'),
  (id: 'album_mix',  label: 'Album Mix',      icon: Icons.album,       sub: 'Based on now playing'),
  (id: 'top_month',  label: 'Top This Month', icon: Icons.trending_up, sub: 'Your most played'),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  List<VibeTrack>            _recentTracks = [];
  List<Map<String, dynamic>> _recentAlbums = [];
  List<Map<String, dynamic>> _topAlbums    = [];
  List<Map<String, dynamic>> _artists      = [];
  bool    _loading = true;
  String? _error;

  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _loadData();
    RecentlyPlayedService.stream.listen((_) {
      if (mounted) setState(() => _recentTracks = RecentlyPlayedService.tracks);
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  Animation<double> _sec(int i) => CurvedAnimation(
    parent: _enterCtrl,
    curve: Interval(
      (i * 0.12).clamp(0.0, 0.8),
      ((i * 0.12) + 0.55).clamp(0.0, 1.0),
      curve: Curves.easeOut,
    ),
  );

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        JellyfinApi.getRecentAlbums(),
        JellyfinApi.getTopAlbums(),
        JellyfinApi.getArtists(),
        JellyfinApi.getAIArtists(),   // used only to exclude AI artists from Home
      ]);
      if (!mounted) return;

      // Build exclusion sets from AI artists — both ID and name for maximum coverage
      final aiArtists = (results[3]['Items'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final aiArtistIds   = aiArtists.map((a) => a['Id']   as String? ?? '').toSet();
      final aiArtistNames = aiArtists.map((a) => (a['Name'] as String? ?? '').trim().toLowerCase()).toSet();

      final seen = <String>{};
      final artists = (results[2]['Items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((a) {
            final name = (a['Name'] as String? ?? '').trim();
            final id   = a['Id'] as String? ?? '';
            if (aiArtistIds.contains(id))                   return false;
            if (aiArtistNames.contains(name.toLowerCase())) return false;
            if (name.isEmpty || name.contains(','))         return false;
            return seen.add(name.toLowerCase());
          })
          .toList();

      setState(() {
        _recentTracks = RecentlyPlayedService.tracks;
        _recentAlbums = (results[0]['Items'] as List? ?? []).cast();
        _topAlbums    = (results[1]['Items'] as List? ?? []).cast();
        _artists      = artists;
        _loading      = false;
      });
      _enterCtrl.forward(from: 0);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _playAlbum(Map<String, dynamic> album) async {
    if (!mounted) return;
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    try {
      final result = await JellyfinApi.getAlbumTracks(album['Id'] as String);
      final tracks = ((result['Items'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VibeTrack.fromJellyfin)
          .toList();
      if (tracks.isEmpty) return;
      ref.read(audioHandlerProvider).playTracks(tracks);
    } catch (e) {
      debugPrint('playAlbum error: $e');
    }
  }

  Future<void> _playTrack(int index) async {
    if (_recentTracks.isEmpty || !mounted) return;
    ref.read(isAIProvider.notifier).state = false;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    ref.read(audioHandlerProvider).playTracks(
      _recentTracks, startIndex: index.clamp(0, _recentTracks.length - 1),
    );
  }

  Future<void> _playStation(String id) async {
    final handler = ref.read(audioHandlerProvider);
    try {
      switch (id) {
        case 'fire_mix':
          final tracks = ref.read(fireMixProvider).where((t) => !t.isAI).toList();
          if (tracks.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No fire tracks yet — mark songs while listening!')),
              );
            }
            return;
          }
          ref.read(isAIProvider.notifier).state = false;
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player');
          handler.playTracks([...tracks]..shuffle());
          return;

        case 'vibe_radio':
          ref.read(isAIProvider.notifier).state = false;
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player');
          final res = await JellyfinApi.getAllTracks(limit: 500);
          final tracks = ((res['Items'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
              .map(VibeTrack.fromJellyfin)
              .toList()..shuffle();
          if (tracks.isEmpty) return;
          handler.playTracks(tracks);
          return;

        case 'artist_mix':
          if (mounted) context.push('/mix/artist');
          return;

        case 'album_mix':
          if (mounted) context.push('/mix/album');
          return;

        case 'top_month':
          ref.read(isAIProvider.notifier).state = false;
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player');
          final res = await JellyfinApi.getTopTracks(limit: 50);
          final tracks = ((res['Items'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
              .map(VibeTrack.fromJellyfin)
              .toList();
          if (tracks.isEmpty) return;
          handler.playTracks(tracks);
          return;
      }
    } catch (e) {
      debugPrint('_playStation $id error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Stack(
      children: [
        // Breathing glow
        Positioned(
          top: 0, left: 0, right: 0,
          child: VibeBreathingGlow(color: theme.accent),
        ),

        if (_loading)
          const Positioned.fill(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Positioned.fill(child: _ErrorState(error: _error!, theme: theme, onRetry: _loadData))
        else
          RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: EdgeInsets.only(
                top:    8,
                bottom: MediaQuery.of(context).padding.bottom + 100,
              ),
              children: [

                // Artist Corner
                if (_artists.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  VibeFadeSlide(animation: _sec(0),
                    child: VibeSectionHeader(title: 'Artist Corner', theme: theme)),
                  const SizedBox(height: 14),
                  VibeFadeSlide(animation: _sec(0),
                    child: SizedBox(
                      height: _kArtistSize + 50,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _artists.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) {
                          final a = _artists[i];
                          return VibeArtistCard(
                            artist: a, theme: theme,
                            onPress: () => context.push(
                              '/artist/${a['Id']}?name=${Uri.encodeComponent(a['Name'] as String? ?? '')}',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // Recently Played
                if (_recentTracks.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(animation: _sec(1),
                    child: VibeSectionHeader(title: 'Recently Played', theme: theme)),
                  const SizedBox(height: 8),
                  VibeFadeSlide(animation: _sec(1),
                    child: Column(
                      children: _recentTracks.take(7).toList().asMap().entries.map(
                        (e) => VibeTrackRow(
                          track: {
                            'Name':        e.value.title,
                            'AlbumArtist': e.value.artist,
                            'AlbumId':     e.value.albumId,
                            'Id':          e.value.id,
                          },
                          theme: theme,
                          onPress: () => _playTrack(e.key),
                        ),
                      ).toList(),
                    ),
                  ),
                ],

                // Recently Added
                if (_recentAlbums.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(animation: _sec(2),
                    child: VibeSectionHeader(title: 'Recently Added in ViBE', theme: theme)),
                  const SizedBox(height: 14),
                  VibeFadeSlide(animation: _sec(2),
                    child: SizedBox(
                      height: _kAlbumSize + 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _recentAlbums.take(10).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => VibeAlbumCard(
                          item: _recentAlbums[i], theme: theme,
                          onPress: () => _playAlbum(_recentAlbums[i]),
                        ),
                      ),
                    ),
                  ),
                ],

                // Stations
                const SizedBox(height: 28),
                VibeFadeSlide(animation: _sec(3),
                  child: VibeSectionHeader(title: 'Stations', theme: theme)),
                const SizedBox(height: 14),
                VibeFadeSlide(animation: _sec(3),
                  child: VibeStationGrid(
                    stations: _kStations,
                    theme:    theme,
                    onTap:    _playStation,
                  ),
                ),

                // Top Albums
                if (_topAlbums.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  VibeFadeSlide(animation: _sec(4),
                    child: VibeSectionHeader(title: 'Top Albums', theme: theme)),
                  const SizedBox(height: 14),
                  VibeFadeSlide(animation: _sec(4),
                    child: SizedBox(
                      height: _kAlbumSize + 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _topAlbums.take(10).length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, i) => VibeAlbumCard(
                          item: _topAlbums[i], theme: theme,
                          onPress: () => _playAlbum(_topAlbums[i]),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String error;
  final VibeTheme theme;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.theme, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: theme.textFaint),
          const SizedBox(height: 16),
          Text('Could not reach Jellyfin',
              style: TextStyle(color: theme.textColor, fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textFaint, fontSize: 11)),
          const SizedBox(height: 24),
          VibeBounce(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color:        theme.accent,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: theme.accent.withAlpha(0x66), blurRadius: 14),
                ],
              ),
              child: Text('Retry',
                  style: TextStyle(color: theme.textColor, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );
}
