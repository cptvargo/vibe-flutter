import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../config/artist_images.dart';
import '../providers.dart';
import '../theme/vibe_theme.dart';

const double _kAlbumCard  = 140;
const double _kArtistSize = 80;

// ── Section header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VibeTheme theme;
  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: TextStyle(
          color: theme.textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ── Album card ─────────────────────────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VibeTheme theme;
  final VoidCallback? onPress;
  const _AlbumCard({required this.item, required this.theme, this.onPress});

  @override
  Widget build(BuildContext context) {
    final itemId = item['Id'] as String? ?? '';
    final artUrl = itemId.isNotEmpty ? JellyfinApi.imageUrl(itemId, size: 300) : null;

    return GestureDetector(
      onTap: onPress,
      child: SizedBox(
        width: _kAlbumCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImageBox(url: artUrl, size: _kAlbumCard, radius: 10,
                surface: theme.surface, border: theme.border),
            const SizedBox(height: 8),
            Text(item['Name'] as String? ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.textColor, fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(
              item['AlbumArtist'] as String?
                  ?? (item['Artists'] as List?)?.firstOrNull as String? ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Artist circle card ─────────────────────────────────────────────────────
class _ArtistCard extends StatelessWidget {
  final Map<String, dynamic> artist;
  final VibeTheme theme;
  final VoidCallback? onPress;
  const _ArtistCard({required this.artist, required this.theme, this.onPress});

  @override
  Widget build(BuildContext context) {
    final id        = artist['Id'] as String? ?? '';
    final name      = artist['Name'] as String? ?? '';
    final localAsset = kArtistImages[name];
    final remoteUrl  = id.isNotEmpty ? JellyfinApi.imageUrl(id, size: 200) : null;

    return GestureDetector(
      onTap: onPress,
      child: SizedBox(
        width: _kArtistSize + 8,
        child: Column(
          children: [
            Container(
              width: _kArtistSize, height: _kArtistSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: localAsset != null
                  ? Image.asset(localAsset, fit: BoxFit.cover,
                      width: _kArtistSize, height: _kArtistSize)
                  : remoteUrl != null
                      ? CachedNetworkImage(imageUrl: remoteUrl, fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: theme.surface),
                          errorWidget: (_, _, _) => Container(color: theme.surface))
                      : Container(color: theme.surface),
            ),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Track row ──────────────────────────────────────────────────────────────
class _TrackRow extends StatelessWidget {
  final Map<String, dynamic> track;
  final VibeTheme theme;
  final VoidCallback? onPress;
  const _TrackRow({required this.track, required this.theme, this.onPress});

  @override
  Widget build(BuildContext context) {
    final albumId = track['AlbumId'] as String?
        ?? track['ParentId'] as String?
        ?? track['Id'] as String? ?? '';
    final artUrl = albumId.isNotEmpty ? JellyfinApi.imageUrl(albumId, size: 100) : null;

    return GestureDetector(
      onTap: onPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _ImageBox(url: artUrl, size: 48, radius: 6,
                surface: theme.surface, border: theme.border),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track['Name'] as String? ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textColor, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    track['AlbumArtist'] as String?
                        ?? (track['Artists'] as List?)?.firstOrNull as String? ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Station card ────────────────────────────────────────────────────────────
// Uses Material icons instead of emoji — emoji rendering is unreliable on
// Windows desktop and some Android configurations.
const _kStations = [
  (id: 'fire_mix',   label: 'Fire Mix',       icon: Icons.whatshot,    sub: 'Your marked bangers'),
  (id: 'vibe_radio', label: 'ViBE Radio',     icon: Icons.radio,       sub: 'Your full library'),
  (id: 'artist_mix', label: 'Artist Mix',     icon: Icons.mic_none,    sub: 'Based on now playing'),
  (id: 'album_mix',  label: 'Album Mix',      icon: Icons.album,       sub: 'Based on now playing'),
  (id: 'top_month',  label: 'Top This Month', icon: Icons.trending_up, sub: 'Your most played'),
];

class _StationCard extends StatelessWidget {
  final ({String id, String label, IconData icon, String sub}) station;
  final VibeTheme theme;
  final VoidCallback? onTap;
  const _StationCard({required this.station, required this.theme, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.accent.withAlpha(0x99)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(station.icon, size: 26,
                color: station.id == 'fire_mix'
                    ? const Color(0xFFFF6B1A)
                    : theme.accentBright),
            const SizedBox(height: 8),
            Text(station.label,
                style: TextStyle(color: theme.textColor, fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(station.sub,
                style: TextStyle(color: theme.textFaint, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Shared image box ────────────────────────────────────────────────────────
class _ImageBox extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final Color surface;
  final Color border;
  const _ImageBox({this.url, required this.size, required this.radius,
      required this.surface, required this.border});

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      color: surface,
    );
    if (url == null) {
      return Container(width: size, height: size, decoration: decoration);
    }
    return CachedNetworkImage(
      imageUrl: url!, width: size, height: size, fit: BoxFit.cover,
      imageBuilder: (_, provider) => Container(
        width: size, height: size,
        decoration: decoration.copyWith(
          image: DecorationImage(image: provider, fit: BoxFit.cover),
        ),
      ),
      placeholder: (_, _) =>
          Container(width: size, height: size, decoration: decoration),
      errorWidget: (_, _, _) =>
          Container(width: size, height: size, decoration: decoration),
    );
  }
}

// ── Home screen ────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Map<String, dynamic>> _recentTracks = [];
  List<Map<String, dynamic>> _recentAlbums = [];
  List<Map<String, dynamic>> _topAlbums    = [];
  List<Map<String, dynamic>> _artists      = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        JellyfinApi.getRecentlyPlayed(),
        JellyfinApi.getRecentAlbums(),
        JellyfinApi.getTopAlbums(),
        JellyfinApi.getArtists(),
      ]);
      if (!mounted) return;

      final seen = <String>{};
      final artists = (results[3]['Items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((a) {
            final name = (a['Name'] as String? ?? '').trim();
            if (name.isEmpty || name.contains(',')) return false;
            return seen.add(name.toLowerCase());
          })
          .toList();

      setState(() {
        _recentTracks = (results[0]['Items'] as List? ?? []).cast();
        _recentAlbums = (results[1]['Items'] as List? ?? []).cast();
        _topAlbums    = (results[2]['Items'] as List? ?? []).cast();
        _artists      = artists;
        _loading      = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _playAlbum(Map<String, dynamic> album) async {
    if (!mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player'); // open instantly
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
    final tracks = _recentTracks.map(VibeTrack.fromJellyfin).toList();
    if (tracks.isEmpty || !mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player'); // open instantly
    ref.read(audioHandlerProvider).playTracks(
      tracks, startIndex: index.clamp(0, tracks.length - 1),
    );
  }

  Future<void> _playStation(String id) async {
    final handler = ref.read(audioHandlerProvider);
    try {
      switch (id) {
        case 'fire_mix':
          final tracks = ref.read(fireMixProvider);
          if (tracks.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No fire tracks yet — mark songs while listening!')),
              );
            }
            return;
          }
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player'); // open instantly
          handler.playTracks([...tracks]..shuffle());
          return;

        case 'vibe_radio':
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player'); // open instantly
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
          ref.read(playerOpenProvider.notifier).state = true;
          if (mounted) context.push('/player'); // open instantly
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
    final theme   = ref.watch(themeProvider);
    final screenH = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        // Accent glow at top
        Positioned(
          top: 0, left: 0, right: 0,
          height: screenH * 0.45,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.accent.withAlpha(0x36),
                  theme.accent.withAlpha(0x0F),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.7],
              ),
            ),
          ),
        ),

        if (_loading)
          const Positioned.fill(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Positioned.fill(child: _ErrorState(error: _error!, theme: theme, onRetry: _loadData))
        else
          ListView(
            padding: EdgeInsets.only(
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 100,
            ),
            children: [

              // Artist Corner
              if (_artists.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionHeader(title: 'Artist Corner', theme: theme),
                const SizedBox(height: 14),
                SizedBox(
                  height: _kArtistSize + 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _artists.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final a = _artists[i];
                      return _ArtistCard(
                        artist: a, theme: theme,
                        onPress: () => context.push(
                          '/artist/${a['Id']}?name=${Uri.encodeComponent(a['Name'] as String? ?? '')}',
                        ),
                      );
                    },
                  ),
                ),
              ],

              // Recently Played
              if (_recentTracks.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionHeader(title: 'Recently Played', theme: theme),
                const SizedBox(height: 8),
                ..._recentTracks.take(7).toList().asMap().entries.map(
                  (e) => _TrackRow(
                    track: e.value, theme: theme,
                    onPress: () => _playTrack(e.key),
                  ),
                ),
              ],

              // Recently Added
              if (_recentAlbums.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionHeader(title: 'Recently Added in ViBE', theme: theme),
                const SizedBox(height: 14),
                SizedBox(
                  height: _kAlbumCard + 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _recentAlbums.take(10).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => _AlbumCard(
                      item: _recentAlbums[i], theme: theme,
                      onPress: () => _playAlbum(_recentAlbums[i]),
                    ),
                  ),
                ),
              ],

              // Stations — always shown, data is hardcoded
              const SizedBox(height: 28),
              _SectionHeader(title: 'Stations', theme: theme),
              const SizedBox(height: 14),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _kStations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _StationCard(
                    station: _kStations[i],
                    theme: theme,
                    onTap: () => _playStation(_kStations[i].id),
                  ),
                ),
              ),

              // Top Albums
              if (_topAlbums.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionHeader(title: 'Top Albums', theme: theme),
                const SizedBox(height: 14),
                SizedBox(
                  height: _kAlbumCard + 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _topAlbums.take(10).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => _AlbumCard(
                      item: _topAlbums[i], theme: theme,
                      onPress: () => _playAlbum(_topAlbums[i]),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),
            ],
          ),
      ],
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String error;
  final VibeTheme theme;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.theme, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
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
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(24),
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
}
