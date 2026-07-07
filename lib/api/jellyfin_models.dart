import '../api/jellyfin_api.dart';

// A track ready for playback — equivalent to toTrackPlayerTrack() in RN
class VibeTrack {
  final String id;
  final String url;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final String? artistId;
  final String artworkUrl;
  final String colorUrl;   // 32px thumbnail for fast color extraction
  final String? blurHash;
  final Duration duration;
  final Map<String, dynamic> raw;
  final bool isAI;

  const VibeTrack({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    this.albumId,
    this.artistId,
    required this.artworkUrl,
    required this.colorUrl,
    this.blurHash,
    required this.duration,
    required this.raw,
    this.isAI = false,
  });

  factory VibeTrack.fromJson(Map<String, dynamic> j) => VibeTrack(
    id:         j['id']         as String,
    url:        j['url']        as String,
    title:      j['title']      as String,
    artist:     j['artist']     as String,
    album:      j['album']      as String,
    albumId:    j['albumId']    as String?,
    artistId:   j['artistId']   as String?,
    artworkUrl: j['artworkUrl'] as String,
    colorUrl:   j['colorUrl']   as String,
    blurHash:   j['blurHash']   as String?,
    duration:   Duration(microseconds: j['durationMicros'] as int),
    raw:        {},
    isAI:       j['isAI']       as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id':            id,
    'url':           url,
    'title':         title,
    'artist':        artist,
    'album':         album,
    'albumId':       albumId,
    'artistId':      artistId,
    'artworkUrl':    artworkUrl,
    'colorUrl':      colorUrl,
    'blurHash':      blurHash,
    'durationMicros': duration.inMicroseconds,
    'isAI':          isAI,
  };

  factory VibeTrack.fromJellyfin(Map<String, dynamic> j, {bool isAI = false}) {
    final albumId   = j['AlbumId'] as String? ?? j['ParentId'] as String? ?? j['Id'] as String;
    final blurMap   = (j['ImageBlurHashes'] as Map?)?['Primary'] as Map?;
    final blurHash  = blurMap != null ? blurMap.values.firstOrNull as String? : null;
    final ticks     = j['RunTimeTicks'] as int? ?? 0;
    final artistItems = (j['ArtistItems'] as List?)?.cast<Map<String, dynamic>>();
    final artistId  = artistItems?.firstOrNull?['Id'] as String?
                      ?? (j['AlbumArtistIds'] as List?)?.firstOrNull as String?;

    return VibeTrack(
      id:          j['Id'] as String,
      url:         JellyfinApi.streamUrl(j['Id'] as String),
      title:       ((j['Name'] as String?) ?? 'Unknown').split(' | ').first.trim(),
      artist:      j['AlbumArtist'] as String?
                     ?? (j['Artists'] as List?)?.firstOrNull as String?
                     ?? 'Unknown',
      album:       j['Album'] as String? ?? '',
      albumId:     albumId,
      artistId:    artistId,
      artworkUrl:  JellyfinApi.imageUrl(albumId, size: 600),
      colorUrl:    JellyfinApi.colorExtractionUrl(albumId),
      blurHash:    blurHash,
      duration:    Duration(microseconds: (ticks / 10).round()),
      raw:         j,
      isAI:        isAI,
    );
  }
}
