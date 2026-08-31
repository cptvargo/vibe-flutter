import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/jellyfin_config.dart';
import '../services/genre_cluster_service.dart';
import 'jellyfin_models.dart';

// Thrown when Jellyfin returns 401 — token expired or revoked.
class JellyfinAuthException implements Exception {
  const JellyfinAuthException();
}

// Jellyfin API service — all credentials come from JellyfinConfig at runtime.
// No hardcoded values: each user authenticates against their own server.
class JellyfinApi {
  static String get _base => JellyfinConfig.serverUrl;
  static String get _key  => JellyfinConfig.apiKey;
  static String get _user => JellyfinConfig.userId;

  // Library-scoped query fragments — empty for own-server users (no filtering needed)
  static String get _lp   => JellyfinConfig.libParam;    // e.g. '&ParentId=xxx' or ''
  static String get _alp  => JellyfinConfig.aiLibParam;

  // Direct field references (for endpoints that need the raw ID)
  static String get _aiLib => JellyfinConfig.aiLib;

  static Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    'Accept':        'application/json',
    'User-Agent':    'Jellyfin/10.9 (Vibe; Flutter)',
    'X-Emby-Authorization':
        'MediaBrowser Client="Vibe", Device="VibeApp", DeviceId="vibe-flutter-001", Version="1.0.0", Token="$_key"',
  };

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: _headers);
    if (res.statusCode == 401) throw const JellyfinAuthException();
    if (res.statusCode != 200) {
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

  static String colorExtractionUrl(String itemId) =>
      '$_base/Items/$itemId/Images/Primary?fillHeight=32&fillWidth=32&quality=50&api_key=$_key';

  static String streamUrl(String itemId) =>
      '$_base/Audio/$itemId/stream?static=true&api_key=$_key&UserId=$_user&Container=m4a,mp3,flac,wav,aac';

  static String downloadUrl(String itemId) =>
      '$_base/Items/$itemId/Download?api_key=$_key&UserId=$_user';

  // ── Library queries ────────────────────────────────────────────────────────
  // ParentId is appended only when a library ID is configured. Own-server
  // users have no library filter — their server is entirely theirs.

  static Future<Map<String, dynamic>> getRecentlyPlayed({int limit = 20}) =>
      _get('/Users/$_user/Items?SortBy=DatePlayed&SortOrder=Descending'
          '&IncludeItemTypes=Audio&Limit=$limit&Recursive=true'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId,ArtistItems,AlbumArtistIds&IsPlayed=true&Filters=IsPlayed$_lp');

  static Future<Map<String, dynamic>> getRecentAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?SortBy=DateCreated&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio$_lp');

  static Future<Map<String, dynamic>> getTopAlbums({int limit = 20}) =>
      _get('/Users/$_user/Items?SortBy=PlayCount&SortOrder=Descending'
          '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio$_lp');

  static Future<Map<String, dynamic>> getAlbums({int limit = 200}) =>
      _get('/Users/$_user/Items?IncludeItemTypes=MusicAlbum'
          '&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio&SortBy=SortName$_lp');

  static const _trackFields =
      'PrimaryImageAspectRatio,AudioInfo,ParentId,ArtistItems,AlbumArtistIds,ImageTags,Album,AlbumArtist,Genres';

  static Future<Map<String, dynamic>> getAlbumTracks(String albumId) =>
      _get('/Users/$_user/Items?ParentId=$albumId&IncludeItemTypes=Audio'
          '&Fields=$_trackFields,AlbumId&SortBy=IndexNumber');

  static Future<Map<String, dynamic>> getArtists({int limit = 500}) =>
      _get('/Artists/AlbumArtists?UserId=$_user&Limit=$limit'
          '&Fields=PrimaryImageAspectRatio,Overview,ImageTags&SortBy=SortName$_lp');

  static Future<String?> getArtistIdByName(String name) async {
    try {
      final q   = Uri.encodeComponent(name);
      final res = await _get('/Artists/AlbumArtists?UserId=$_user'
          '&SearchTerm=$q&Limit=1&Fields=PrimaryImageAspectRatio$_lp');
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
      _get('/Users/$_user/Items?IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields&SortBy=SortName$_lp');

  static Future<Map<String, dynamic>> getGenres({int limit = 30}) =>
      _get('/MusicGenres?UserId=$_user&Limit=$limit&SortBy=SortName$_lp');

  static Future<Map<String, dynamic>> getInstantMix(String itemId, {int limit = 50}) =>
      _get('/Items/$itemId/InstantMix?UserId=$_user&Limit=$limit&Fields=$_trackFields');

  static Future<List<VibeTrack>> getInstantMixTracks(String itemId, {int limit = 50}) async {
    try {
      final res = await getInstantMix(itemId, limit: limit);
      return ((res['Items'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VibeTrack.fromJellyfin)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getTopTracks({int limit = 50}) =>
      _get('/Users/$_user/Items?IncludeItemTypes=Audio'
          '&Limit=$limit&Recursive=true&Fields=$_trackFields'
          '&SortBy=PlayCount&SortOrder=Descending&Filters=IsPlayed$_lp');

  // Random tracks from the full library — used by ViBE Out.
  static Future<List<VibeTrack>> getRandomTracks({int limit = 28}) async {
    final res = await _get('/Users/$_user/Items?IncludeItemTypes=Audio'
        '&SortBy=Random&Limit=$limit&Recursive=true&Fields=$_trackFields$_lp');
    return ((res['Items'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(VibeTrack.fromJellyfin)
        .toList();
  }

  // Single item by ID — used to patch stale session album titles.
  static Future<Map<String, dynamic>> getItem(String id) =>
      _get('/Users/$_user/Items/$id');

  // Single track by Jellyfin item ID — used by deep link handler.
  static Future<Map<String, dynamic>> getTrackById(String id) =>
      _get('/Users/$_user/Items/$id?Fields=$_trackFields');

  // ── AI library queries ─────────────────────────────────────────────────────
  // Short-circuit when no AI library is configured (own-server users).

  static Future<Map<String, dynamic>> getAIRecentAlbums({int limit = 20}) {
    if (!JellyfinConfig.hasAiLib) return Future.value(_emptyList());
    return _get('/Users/$_user/Items?SortBy=DateCreated&SortOrder=Descending'
        '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio$_alp');
  }

  static Future<Map<String, dynamic>> getAITopAlbums({int limit = 20}) {
    if (!JellyfinConfig.hasAiLib) return Future.value(_emptyList());
    return _get('/Users/$_user/Items?SortBy=PlayCount&SortOrder=Descending'
        '&IncludeItemTypes=MusicAlbum&Limit=$limit&Recursive=true&Fields=PrimaryImageAspectRatio$_alp');
  }

  static Future<Map<String, dynamic>> getAIArtists({int limit = 200}) {
    if (!JellyfinConfig.hasAiLib) return Future.value(_emptyList());
    return _get('/Artists/AlbumArtists?UserId=$_user&ParentId=$_aiLib&Limit=$limit'
        '&Fields=PrimaryImageAspectRatio,Overview,ImageTags&SortBy=SortName');
  }

  static Future<Map<String, dynamic>> getAIAllTracks({int limit = 500}) {
    if (!JellyfinConfig.hasAiLib) return Future.value(_emptyList());
    return _get('/Users/$_user/Items?IncludeItemTypes=Audio'
        '&Limit=$limit&Recursive=true&Fields=$_trackFields&SortBy=SortName$_alp');
  }

  static Future<Map<String, dynamic>> getAITopTracks({int limit = 50}) {
    if (!JellyfinConfig.hasAiLib) return Future.value(_emptyList());
    return _get('/Users/$_user/Items?IncludeItemTypes=Audio'
        '&Limit=$limit&Recursive=true&Fields=$_trackFields'
        '&SortBy=PlayCount&SortOrder=Descending&Filters=IsPlayed$_alp');
  }

  static Future<String?> getAIArtistIdByName(String name) async {
    if (!JellyfinConfig.hasAiLib) return null;
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

  static Map<String, dynamic> _emptyList() =>
      {'Items': <dynamic>[], 'TotalRecordCount': 0};

  // ── Genre similarity ───────────────────────────────────────────────────────

  /// Raw album list used by [GenreClusterService] and [getSimilarArtistsByGenre].
  static Future<List<Map<String, dynamic>>> getAllAlbumsRaw() async {
    final res = await _get(
        '/Users/$_user/Items?IncludeItemTypes=MusicAlbum'
        '&Recursive=true&Fields=Genres,AlbumArtist,AlbumArtists&Limit=2000$_lp');
    return ((res['Items'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getSimilarArtistsByGenre(
      String artistId, {String? albumId, String? artistName, int limit = 8}) async {
    try {
      final excludeName = (artistName ?? '').toLowerCase().trim();
      final albums      = await getAllAlbumsRaw();

      // Prime the cluster cache with these albums so other features that call
      // GenreClusterService later don't need a second round-trip.
      GenreClusterService.buildFromAlbums(albums);

      final artistGenres  = <String, Set<String>>{};
      final artistNames   = <String, String>{};
      final albumToArtist = <String, String>{};

      for (final album in albums) {
        final artists = (album['AlbumArtists'] as List?)?.cast<Map<String, dynamic>>();
        final aId    = artists?.firstOrNull?['Id'] as String? ?? '';
        final aName  = (album['AlbumArtist'] as String? ?? '').trim();
        final albId  = album['Id'] as String? ?? '';
        if (aId.isEmpty) continue;
        final gs = (album['Genres'] as List? ?? [])
            .cast<String>()
            .map((g) => g.toLowerCase().trim())
            .where((g) => !GenreClusterService.isGeneric(g))
            .toSet();
        artistGenres.putIfAbsent(aId, () => {}).addAll(gs);
        artistNames[aId] = aName;
        if (albId.isNotEmpty) albumToArtist[albId] = aId;
      }

      final resolvedId    = (albumId != null ? albumToArtist[albumId] : null) ?? artistId;
      final currentGenres = artistGenres[resolvedId] ?? {};
      final cluster       = GenreClusterService.clusterFor(currentGenres);

      if (cluster == null) {
        return _randomOtherArtists(artistId, excludeName: excludeName, limit: limit);
      }

      final candidates = artistGenres.entries.toList()..shuffle();
      final result     = <Map<String, dynamic>>[];
      final seenIds    = <String>{resolvedId, artistId};
      final seenNames  = <String>{};

      for (final entry in candidates) {
        if (result.length >= limit) break;
        final aId   = entry.key;
        final aName = (artistNames[aId] ?? '').trim();
        final aLow  = aName.toLowerCase();
        if (!seenIds.add(aId)) continue;
        if (!seenNames.add(aLow)) continue;
        if (excludeName.isNotEmpty && aLow.contains(excludeName)) continue;
        if (entry.value.any(cluster.containsGenre)) {
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
      final res = await _get('/Artists/AlbumArtists?UserId=$_user'
          '&Limit=200&Fields=ImageTags&SortBy=SortName$_lp');
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

  // ── Playlists ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPlaylists() =>
      _get('/Users/$_user/Items?IncludeItemTypes=Playlist&Recursive=true'
          '&Fields=PrimaryImageAspectRatio,ChildCount,ImageTags'
          '&SortBy=SortName&SortOrder=Ascending');

  static Future<Map<String, dynamic>> createPlaylist(String name) async {
    final res = await http.post(
      Uri.parse('$_base/Playlists'),
      headers: _headers,
      body: json.encode({'Name': name, 'UserId': _user, 'MediaType': 'Audio'}),
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return json.decode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await http.delete(Uri.parse('$_base/Items/$playlistId'), headers: _headers);
  }

  static Future<Map<String, dynamic>> getPlaylistItems(String playlistId) =>
      _get('/Playlists/$playlistId/Items?UserId=$_user'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId,ImageTags'
          '&Limit=500');

  static Future<void> addToPlaylist(String playlistId, List<String> itemIds) async {
    final ids = itemIds.join(',');
    final res = await http.post(
      Uri.parse('$_base/Playlists/$playlistId/Items?Ids=$ids&UserId=$_user'),
      headers: _headers,
    );
    if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
  }

  static Future<void> removeFromPlaylist(String playlistId, List<String> entryIds) async {
    final ids = entryIds.join(',');
    await http.delete(
      Uri.parse('$_base/Playlists/$playlistId/Items?EntryIds=$ids'),
      headers: _headers,
    );
  }

  static Future<List<Map<String, dynamic>>> searchTracks(String query, {int limit = 30}) async {
    final q   = Uri.encodeComponent(query);
    final res = await _get('/Users/$_user/Items?SearchTerm=$q'
        '&IncludeItemTypes=Audio&Limit=$limit&Recursive=true'
        '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId,ImageTags$_lp');
    return (res['Items'] as List).cast<Map<String, dynamic>>();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> search(String query, {int limit = 40}) async {
    final q = Uri.encodeComponent(query);
    final results = await Future.wait([
      _get('/Users/$_user/Items?SearchTerm=$q'
          '&IncludeItemTypes=Audio,MusicAlbum&Limit=$limit&Recursive=true'
          '&Fields=PrimaryImageAspectRatio,AudioInfo,ParentId$_lp'),
      _get('/Artists/AlbumArtists?UserId=$_user&SearchTerm=$q'
          '&Limit=10&Fields=PrimaryImageAspectRatio,ImageTags$_lp'),
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

  // ── Jellyfin authentication ────────────────────────────────────────────────
  // Used during "Own Server" and "Join ViBE" signup to get an access token.

  static Future<({String token, String userId})?> authenticateByName({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final base = serverUrl.replaceAll(RegExp(r'/$'), '');
      final res  = await http.post(
        Uri.parse('$base/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization':
              'MediaBrowser Client="Vibe", Device="VibeApp", '
              'DeviceId="vibe-flutter-001", Version="1.0.0"',
        },
        body: json.encode({'Username': username, 'Pw': password}),
      );
      if (res.statusCode != 200) return null;
      final data   = json.decode(res.body) as Map<String, dynamic>;
      final token  = data['AccessToken'] as String?;
      final uid    = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;
      if (token == null || uid == null) return null;
      return (token: token, userId: uid);
    } catch (_) {
      return null;
    }
  }
}
