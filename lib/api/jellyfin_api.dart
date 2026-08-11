import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/vibe_config.dart';

// Jellyfin API service — translated from jellyfin.js
class JellyfinApi {
  static const _lib   = VibeConfig.vibeLibrary;
  static const _aiLib = VibeConfig.aiLibrary;
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

  static String imageUrl(String itemId, {String type = 'Primary', int size = 400, String? tag}) {
    final base = '$_base/Items/$itemId/Images/$type?fillHeight=$size&fillWidth=$size&quality=90&api_key=$_key';
    return tag != null ? '$base&tag=$tag' : base;
  }

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

  static const _trackFields =
      'PrimaryImageAspectRatio,AudioInfo,ParentId,ArtistItems,AlbumArtistIds,ImageTags';

  static Future<Map<String, dynamic>> getAlbumTracks(String albumId) =>
      _get('/Users/$_user/Items?ParentId=$albumId&IncludeItemTypes=Audio'
          '&Fields=$_trackFields,AlbumId&SortBy=IndexNumber');

  static Future<Map<String, dynamic>> getArtists({int limit = 200}) =>
      _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_lib&Limit=$limit'
          '&Fields=PrimaryImageAspectRatio,Overview,ImageTags&SortBy=SortName');

  static Future<String?> getArtistIdByName(String name) async {
    try {
      final q   = Uri.encodeComponent(name);
      final res = await _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_lib'
          '&SearchTerm=$q&Limit=1&Fields=PrimaryImageAspectRatio');
      final items = (res['Items'] as List?) ?? [];
      if (items.isEmpty) return null;
      return (items.first as Map<String, dynamic>)['Id'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getArtistAlbums(String artistId) =>
      _get('/Users/$_user/Items?AlbumArtistIds=$artistId&IncludeItemTypes=MusicAlbum'
          '&Recursive=true&Fields=PrimaryImageAspectRatio&SortBy=ProductionYear&SortOrder=Descending');

  static Future<Map<String, dynamic>> getArtistTracks(String artistId, {int limit = 30}) =>
      _get('/Users/$_user/Items?ArtistIds=$artistId&IncludeItemTypes=Audio'
          '&Recursive=true&Fields=$_trackFields&SortBy=Random&Limit=$limit');

  static Future<Map<String, dynamic>> getArtistAllTracks(String artistId) =>
      _get('/Users/$_user/Items?AlbumArtistIds=$artistId&IncludeItemTypes=Audio'
          '&Recursive=true&Fields=$_trackFields,AlbumId'
          '&SortBy=ProductionYear,ParentIndexNumber,IndexNumber&SortOrder=Descending,Ascending,Ascending&Limit=500');

  static Future<Map<String, dynamic>> getAllTracks({int limit = 500}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields&SortBy=SortName');

  static Future<Map<String, dynamic>> getGenres({int limit = 30}) =>
      _get('/MusicGenres?UserId=$_user&ParentId=$_lib&Limit=$limit&SortBy=SortName');

  static Future<Map<String, dynamic>> getInstantMix(String itemId, {int limit = 50}) =>
      _get('/Items/$itemId/InstantMix?UserId=$_user&Limit=$limit&Fields=$_trackFields');

  static Future<Map<String, dynamic>> getTopTracks({int limit = 50}) =>
      _get('/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields'
          '&SortBy=PlayCount&SortOrder=Descending&Filters=IsPlayed');

  // ── AI library queries ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAIRecentAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?ParentId=$_aiLib&SortBy=DateCreated&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio');

  static Future<Map<String, dynamic>> getAITopAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?ParentId=$_aiLib&SortBy=PlayCount&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio');

  static Future<Map<String, dynamic>> getAIArtists({int limit = 200}) =>
      _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_aiLib&Limit=$limit'
          '&Fields=PrimaryImageAspectRatio,Overview,ImageTags&SortBy=SortName');

  static Future<Map<String, dynamic>> getAIAllTracks({int limit = 500}) =>
      _get('/Users/$_user/Items?ParentId=$_aiLib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields&SortBy=SortName');

  static Future<Map<String, dynamic>> getAITopTracks({int limit = 50}) =>
      _get('/Users/$_user/Items?ParentId=$_aiLib&IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields'
          '&SortBy=PlayCount&SortOrder=Descending&Filters=IsPlayed');

  // Genre buckets — Jellyfin's Genres filter does substring matching, so
  // "Contemporary Christian" also returns "Christian Hip-Hop" albums.
  // We fetch all albums once and do exact bucket matching client-side.
  static const _hipHopGenres = {
    'christian hip-hop', 'hip-hop', 'rap', 'christian rap',
    'hip-hop/rap', 'christian/rap', 'trap',
  };
  static const _worshipGenres = {
    'contemporary christian', 'praise & worship', 'worship',
    'gospel', 'ccm', 'christian pop',
  };
  static const _genericGenres = {'music', 'christian', ''};

  static Future<List<Map<String, dynamic>>> getSimilarArtistsByGenre(
      String artistId, {String? albumId, String? artistName, int limit = 8}) async {
    try {
      final excludeName = (artistName ?? '').toLowerCase().trim();

      // One call — fetch all albums with genres + album artist info.
      // Note: Jellyfin returns AlbumArtists [{Name,Id}] not AlbumArtistIds.
      final res = await _get(
          '/Users/$_user/Items?ParentId=$_lib&IncludeItemTypes=MusicAlbum'
          '&Recursive=true&Fields=Genres,AlbumArtist,AlbumArtists&Limit=500');
      final albums = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();

      // Build albumArtistId → {specific genres} map (skip generic catch-alls).
      // Also build a reverse map: albumId → albumArtistId so we can resolve the
      // correct artist ID even when the track's ArtistItems ID differs from the
      // album's AlbumArtistIds (a common Jellyfin inconsistency).
      final artistGenres  = <String, Set<String>>{};
      final artistNames   = <String, String>{};
      final albumToArtist = <String, String>{}; // albumId → albumArtistId
      for (final album in albums) {
        final artists = (album['AlbumArtists'] as List?)?.cast<Map<String, dynamic>>();
        final aId    = artists?.firstOrNull?['Id'] as String? ?? '';
        final aName  = (album['AlbumArtist'] as String? ?? '').trim();
        final albId  = album['Id'] as String? ?? '';
        if (aId.isEmpty) continue;
        final gs = (album['Genres'] as List? ?? [])
            .cast<String>()
            .map((g) => g.toLowerCase().trim())
            .where((g) => !_genericGenres.contains(g))
            .toSet();
        artistGenres.putIfAbsent(aId, () => {}).addAll(gs);
        artistNames[aId] = aName;
        if (albId.isNotEmpty) albumToArtist[albId] = aId;
      }

      // Resolve the current artist: prefer albumId lookup (more reliable),
      // fall back to the track-supplied artistId.
      final resolvedId    = (albumId != null ? albumToArtist[albumId] : null) ?? artistId;
      final currentGenres = artistGenres[resolvedId] ?? {};
      Set<String> bucket;
      if (currentGenres.any(_hipHopGenres.contains)) {
        bucket = _hipHopGenres;
      } else if (currentGenres.any(_worshipGenres.contains)) {
        bucket = _worshipGenres;
      } else {
        // Unknown or no specific genre — fall back to random.
        return _randomOtherArtists(artistId, excludeName: excludeName, limit: limit);
      }

      // Collect artists in the same bucket, shuffled, excluding self.
      final candidates = artistGenres.entries.toList()..shuffle();
      final result     = <Map<String, dynamic>>[];
      final seenIds    = <String>{resolvedId, artistId}; // exclude both IDs for same artist
      final seenNames  = <String>{};

      for (final entry in candidates) {
        if (result.length >= limit) break;
        final aId   = entry.key;
        final aName = (artistNames[aId] ?? '').trim();
        final aLow  = aName.toLowerCase();
        if (!seenIds.add(aId)) continue;
        if (!seenNames.add(aLow)) continue;
        if (excludeName.isNotEmpty && aLow.contains(excludeName)) continue;
        if (entry.value.any(bucket.contains)) {
          result.add({'Id': aId, 'Name': aName});
        }
      }

      if (result.isNotEmpty) return result;
      return _randomOtherArtists(resolvedId, excludeName: excludeName, limit: limit);
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _randomOtherArtists(
      String excludeId, {String excludeName = '', int limit = 8}) async {
    try {
      final res = await _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_lib'
          '&Limit=200&Fields=ImageTags&SortBy=SortName');
      final all = ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
      final filtered = all.where((a) {
        final id  = a['Id']   as String? ?? '';
        final low = (a['Name'] as String? ?? '').toLowerCase();
        if (id == excludeId) return false;
        if (excludeName.isNotEmpty && low.contains(excludeName)) return false;
        return true;
      }).toList()..shuffle();
      return filtered.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> getAIArtistIdByName(String name) async {
    try {
      final q   = Uri.encodeComponent(name);
      final res = await _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_aiLib'
          '&SearchTerm=$q&Limit=1&Fields=PrimaryImageAspectRatio');
      final items = (res['Items'] as List?) ?? [];
      if (items.isEmpty) return null;
      return (items.first as Map<String, dynamic>)['Id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────

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
