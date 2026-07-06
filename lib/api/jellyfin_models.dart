import '../api/jellyfin_api.dart';

// A track ready for playback — equivalent to toTrackPlayerTrack() in RN
class VibeTrack {
  final String id;
  final String url;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final String artworkUrl;
  final String colorUrl;   // 32px thumbnail for fast color extraction
  final String? blurHash;
  final Duration duration;
  final Map<String, dynamic> raw;

  const VibeTrack({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    this.albumId,
    required this.artworkUrl,
    required this.colorUrl,
    this.blurHash,
    required this.duration,
    required this.raw,
  });

  factory VibeTrack.fromJellyfin(Map<String, dynamic> j) {
    final albumId = j['AlbumId'] as String? ?? j['ParentId'] as String? ?? j['Id'] as String;
    final blurMap  = (j['ImageBlurHashes'] as Map?)?['Primary'] as Map?;
    final blurHash = blurMap != null ? blurMap.values.firstOrNull as String? : null;
    final ticks    = j['RunTimeTicks'] as int? ?? 0;

    return VibeTrack(
      id:          j['Id'] as String,
      url:         JellyfinApi.streamUrl(j['Id'] as String),
      title:       j['Name'] as String? ?? 'Unknown',
      artist:      j['AlbumArtist'] as String?
                     ?? (j['Artists'] as List?)?.firstOrNull as String?
                     ?? 'Unknown',
      album:       j['Album'] as String? ?? '',
      albumId:     albumId,
      artworkUrl:  JellyfinApi.imageUrl(albumId, size: 600),
      colorUrl:    JellyfinApi.colorExtractionUrl(albumId),
      blurHash:    blurHash,
      duration:    Duration(microseconds: (ticks / 10).round()),
      raw:         j,
    );
  }
}
