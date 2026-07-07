import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/vibe_config.dart';

// Jellyfin API service — translated from jellyfin.js
class JellyfinApi {
  static const _lib  = VibeConfig.vibeLibrary;
  static const _user = VibeConfig.userId;
  static const _key  = VibeConfig.apiKey;

  static String get _base => VibeConfig.serverUrl;

  static Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    'Accept':        'application/json',
    'User-Agent':    'Jellyfin/10.9 (Vibe; Flutter)',
    'X-Emby-Authorization':
        'MediaBrowser Client="Vibe", Device="VibeApp", DeviceId="vibe-flutter-001", Version="1.0.0", Token="$_key"',
  };

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: _headers);
    if (res.statusCode != 200) {
      // Include a snippet of the body — Cloudflare embeds a 1XXX sub-error
      // code in the HTML body that narrows down why the 530 was returned.
      final snippet = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
      throw Exception('HTTP ${res.statusCode}${ snippet.isNotEmpty ? '\n$snippet' : ''}');
    }
    return json.decode(res.body) as Map<String, dynamic>;
  }

  // ── Image URLs ─────────────────────────────────────────────────────────────

  static String imageUrl(String itemId, {String type = 'Primary', int size = 400}) =>
      '$_base/Items/$itemId/Images/$type?fillHeight=$size&fillWidth=$size&quality=90&api_key=$_key';

  // 32px thumbnail used only for color extraction — ~2KB download
  static String colorExtractionUrl(String itemId) =>
      '$_base/Items/$itemId/Images/Primary?fillHeight=32&fillWidth=32&quality=50&api_key=$_key';

  static String streamUrl(String itemId) =>
      '$_base/Audio/$itemId/stream?static=true&api_key=$_key&UserId=$_user&Container=m4a,mp3,flac,wav,aac';

  // ── Library queries ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getRecentlyPlayed({int limit = 20}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&SortBy=DatePlayed&SortOrder=Descending'
          '&IncludeItemTypes=Audio&Limit=$limit&Recursive=true'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId,ArtistItems,AlbumArtistIds&IsPlayed=true&Filters=IsPlayed');

  static Future<Map<String, dynamic>> getRecentAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&SortBy=DateCreated&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio');

  static Future<Map<String, dynamic>> getTopAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&SortBy=PlayCount&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio');

  static Future<Map<String, dynamic>> getAlbums({int limit = 200}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=MusicAlbum'
          '&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio&SortBy=SortName');

  static Future<Map<String, dynamic>> getAlbumTracks(String albumId) =>
      _get('/Users/$_user/Items?ParentId=$albumId&IncludeItemTypes=Audio'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ArtistItems,AlbumArtistIds&SortBy=IndexNumber');

  static Future<Map<String, dynamic>> getArtists({int limit = 200}) =>
      _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_lib&Limit=$limit'
          '&Fields=PrimaryImageAspectRatio,Overview,ImageTags&SortBy=SortName');

  static Future<Map<String, dynamic>> getArtistAlbums(String artistId) =>
      _get('/Users/$_user/Items?AlbumArtistIds=$artistId&IncludeItemTypes=MusicAlbum'
          '&Recursive=true&Fields=PrimaryImageAspectRatio&SortBy=ProductionYear&SortOrder=Descending');

  static Future<Map<String, dynamic>> getArtistTracks(String artistId, {int limit = 30}) =>
      _get('/Users/$_user/Items?ArtistIds=$artistId&IncludeItemTypes=Audio'
          '&Recursive=true&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId&SortBy=Random&Limit=$limit');

  static Future<Map<String, dynamic>> getArtistAllTracks(String artistId) =>
      _get('/Users/$_user/Items?AlbumArtistIds=$artistId&IncludeItemTypes=Audio'
          '&Recursive=true&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId,AlbumId'
          '&SortBy=ProductionYear,ParentIndexNumber,IndexNumber&SortOrder=Descending,Ascending,Ascending&Limit=500');

  static Future<Map<String, dynamic>> getAllTracks({int limit = 500}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId&SortBy=SortName');

  static Future<Map<String, dynamic>> getGenres({int limit = 30}) =>
      _get('/MusicGenres?UserId=$_user&ParentId=$_lib&Limit=$limit&SortBy=SortName');

  static Future<Map<String, dynamic>> getInstantMix(String itemId, {int limit = 50}) =>
      _get('/Items/$itemId/InstantMix?UserId=$_user&Limit=$limit&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId');

  static Future<Map<String, dynamic>> getTopTracks({int limit = 50}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId'
          '&SortBy=PlayCount&SortOrder=Descending&Filters=IsPlayed');

  static Future<Map<String, dynamic>> search(String query, {int limit = 40}) async {
    final q = Uri.encodeComponent(query);
    final results = await Future.wait([
      _get('/Users/$_user/Items?SearchTerm=$q'
          '&IncludeItemTypes=Audio,MusicAlbum&Limit=$limit&Recursive=true'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId'),
      _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_lib&SearchTerm=$q'
          '&Limit=10&Fields=PrimaryImageAspectRatio,ImageTags'),
    ]);
    final artists = (results[1]['Items'] as List)
        .map((a) => {...(a as Map<String, dynamic>), 'Type': 'MusicArtist'})
        .toList();
    final rest = results[0]['Items'] as List;
    return {'Items': [...artists, ...rest]};
  }

  // ── Playback reporting ─────────────────────────────────────────────────────

  static Future<void> reportPlaybackStart(String itemId) async {
    try {
      await http.post(
        Uri.parse('$_base/Sessions/Playing'),
        headers: _headers,
        body: json.encode({'ItemId': itemId, 'CanSeek': true, 'IsPaused': false}),
      );
    } catch (_) {}
  }

  static Future<void> reportPlaybackProgress(String itemId, int positionTicks) async {
    try {
      await http.post(
        Uri.parse('$_base/Sessions/Playing/Progress'),
        headers: _headers,
        body: json.encode({'ItemId': itemId, 'PositionTicks': positionTicks}),
      );
    } catch (_) {}
  }

  static Future<void> reportPlaybackStopped(String itemId, int positionTicks) async {
    try {
      await http.post(
        Uri.parse('$_base/Sessions/Playing/Stopped'),
        headers: _headers,
        body: json.encode({'ItemId': itemId, 'PositionTicks': positionTicks}),
      );
    } catch (_) {}
  }
}
