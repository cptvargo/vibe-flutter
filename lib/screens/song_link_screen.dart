import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';

// Shown when the app opens via a vibemusic://song/{id} deep link.
// Fetches the track, plays it, then navigates to the player.
class SongLinkScreen extends ConsumerStatefulWidget {
  final String trackId;
  final String title;
  final String artist;

  const SongLinkScreen({
    super.key,
    required this.trackId,
    required this.title,
    required this.artist,
  });

  @override
  ConsumerState<SongLinkScreen> createState() => _SongLinkScreenState();
}

class _SongLinkScreenState extends ConsumerState<SongLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _play();
  }

  Future<void> _play() async {
    try {
      // Fetch full track metadata from Jellyfin
      final res    = await JellyfinApi.getTrackById(widget.trackId);
      final track  = VibeTrack.fromJellyfin(res);

      if (!mounted) return;
      ref.read(playerOpenProvider.notifier).state = true;
      await ref.read(audioHandlerProvider).playTracks(
        [track],
        playbackContext: 'vibe_out',
      );
      if (mounted) context.go('/player');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play this track.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Home',
                        style: TextStyle(color: Color(0xFF7C3AED))),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF7C3AED), strokeWidth: 2),
                  const SizedBox(height: 20),
                  if (widget.title.isNotEmpty)
                    Text(
                      widget.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                  if (widget.artist.isNotEmpty)
                    Text(
                      widget.artist,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                ],
              ),
      ),
    );
  }
}
