import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';
import '../services/genre_cluster_service.dart';

/// A generated playlist of 50 tracks built from a single genre cluster,
/// round-robined across artists so no single artist dominates.
class VibeMix {
  final String        id;
  final String        name;
  final List<VibeTrack> tracks;
  final String        clusterKey; // representative genre tag

  const VibeMix({
    required this.id,
    required this.name,
    required this.tracks,
    required this.clusterKey,
  });

  VibeMix copyWith({String? name}) => VibeMix(
    id:         id,
    name:       name ?? this.name,
    tracks:     tracks,
    clusterKey: clusterKey,
  );
}

/// Generates and caches genre-aware preset mixes from the user's Jellyfin
/// library. Works for any genre combination — no hardcoded genre names.
class PresetMixService {
  static const _cacheKey    = 'preset_mixes_v1';
  static const _namesKey    = 'preset_mix_names_v1';
  static const _dateKey     = 'preset_mixes_date_v1';
  static const _tracksPerMix = 50;
  static const _maxMixes     = 8;
  static const _minClusterSz = 5;

  static List<VibeMix>? _cached;

  /// Returns mixes from cache if fresh (< 24 h), otherwise regenerates.
  static Future<List<VibeMix>> getMixes({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached!;

    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final dateStr = prefs.getString(_dateKey);
      if (dateStr != null) {
        final cacheDate = DateTime.tryParse(dateStr);
        if (cacheDate != null &&
            DateTime.now().difference(cacheDate).inHours < 24) {
          final loaded = _loadFromPrefs(prefs);
          if (loaded.isNotEmpty) {
            _cached = loaded;
            return _cached!;
          }
        }
      }
    }

    final mixes = await _generate(prefs);
    _cached = mixes;
    _saveToPrefs(prefs, mixes);
    return mixes;
  }

  /// Persist a user-chosen name for a mix across regenerations.
  static Future<void> rename(String mixId, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_namesKey);
    final names = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>()
        : <String, String>{};
    names[mixId] = newName;
    await prefs.setString(_namesKey, jsonEncode(names));
    if (_cached != null) {
      _cached = _cached!
          .map((m) => m.id == mixId ? m.copyWith(name: newName) : m)
          .toList();
    }
  }

  /// Drop both the in-memory cache and the SharedPreferences timestamp so the
  /// next [getMixes] call regenerates instead of reloading the stale prefs data.
  static Future<void> invalidate() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dateKey);
    await prefs.remove(_cacheKey);
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  static Future<List<VibeMix>> _generate(SharedPreferences prefs) async {
    final clusters = await GenreClusterService.getClusters();
    if (clusters.isEmpty) return [];

    final res = await JellyfinApi.getAllTracks(limit: 1000);
    final allTracks = ((res['Items'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(VibeTrack.fromJellyfin)
        .toList();

    // Preserve any names the user has saved across a regeneration.
    final raw   = prefs.getString(_namesKey);
    final names = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>()
        : <String, String>{};

    final mixes     = <VibeMix>[];
    int   mixIndex  = 0;

    for (final cluster in clusters) {
      if (mixes.length >= _maxMixes) break;

      // Tracks whose genres meaningfully overlap this cluster.
      final clusterTracks = allTracks.where((t) {
        final genres = ((t.raw['Genres'] as List?) ?? [])
            .cast<String>()
            .map((g) => g.toLowerCase().trim())
            .toSet();
        return cluster.matchesAny(genres) &&
            !genres.every(GenreClusterService.isGeneric);
      }).toList();

      if (clusterTracks.length < _minClusterSz) continue;

      final byArtist   = <String, List<VibeTrack>>{};
      for (final t in clusterTracks) {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }

      final clusterKey = _representativeGenre(cluster);
      final label = _capitalize(clusterKey);

      // Mix 1 — round-robin across all cluster tracks.
      final order1  = byArtist.keys.toList()..sort();
      final tracks1 = _roundRobin(byArtist, order1, _tracksPerMix);
      if (tracks1.length < _minClusterSz) continue;

      final id1 = 'mix_$mixIndex';
      mixes.add(VibeMix(
        id:         id1,
        name:       names[id1] ?? '$label Mix 1',
        tracks:     tracks1,
        clusterKey: clusterKey,
      ));
      mixIndex++;

      // Mix 2 — only generated when there are enough tracks NOT already in Mix 1
      // to form a meaningfully different playlist.
      if (mixes.length < _maxMixes) {
        final usedIds   = tracks1.map((t) => t.id).toSet();
        final remainder = clusterTracks
            .where((t) => !usedIds.contains(t.id))
            .toList();

        if (remainder.length >= _minClusterSz) {
          final byArtist2 = <String, List<VibeTrack>>{};
          for (final t in remainder) {
            byArtist2.putIfAbsent(t.artist, () => []).add(t);
          }
          final order2  = byArtist2.keys.toList()
            ..sort((a, b) => byArtist2[b]!.length.compareTo(byArtist2[a]!.length));
          final tracks2 = _roundRobin(byArtist2, order2, _tracksPerMix);

          if (tracks2.length >= _minClusterSz) {
            final id2 = 'mix_$mixIndex';
            mixes.add(VibeMix(
              id:         id2,
              name:       names[id2] ?? '$label Mix 2',
              tracks:     tracks2,
              clusterKey: clusterKey,
            ));
            mixIndex++;
          }
        }
      }
    }

    return mixes;
  }

  /// Round-robin through artists, taking 2 tracks per pass, until [target]
  /// tracks are collected. Tracks within each artist are shuffled for variety.
  static List<VibeTrack> _roundRobin(
    Map<String, List<VibeTrack>> byArtist,
    List<String> order,
    int target,
  ) {
    final rng  = Random();
    final pool = {
      for (final a in order) a: List.of(byArtist[a]!)..shuffle(rng),
    };
    final result = <VibeTrack>[];
    int pass = 0;

    while (result.length < target) {
      bool contributed = false;
      for (final artist in order) {
        if (result.length >= target) break;
        final ts    = pool[artist] ?? [];
        final start = pass * 2;
        if (start >= ts.length) continue;
        final end = min(start + 2, ts.length);
        result.addAll(ts.sublist(start, end));
        contributed = true;
      }
      if (!contributed) break;
      pass++;
    }

    return result.take(target).toList();
  }

  static String _representativeGenre(GenreCluster cluster) =>
      cluster.genres.reduce((a, b) => a.length <= b.length ? a : b);

  static String _capitalize(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  // ── Persistence ────────────────────────────────────────────────────────────

  static void _saveToPrefs(SharedPreferences prefs, List<VibeMix> mixes) {
    prefs.setStringList(_cacheKey, mixes.map((m) => jsonEncode({
      'id':         m.id,
      'name':       m.name,
      'clusterKey': m.clusterKey,
      'tracks':     m.tracks.map((t) => t.toJson()).toList(),
    })).toList());
    prefs.setString(_dateKey, DateTime.now().toIso8601String());
  }

  static List<VibeMix> _loadFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getStringList(_cacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return raw.map((s) {
        final m = jsonDecode(s) as Map<String, dynamic>;
        return VibeMix(
          id:         m['id'] as String,
          name:       m['name'] as String,
          clusterKey: m['clusterKey'] as String,
          tracks:     ((m['tracks'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
              .map(VibeTrack.fromJson)
              .toList(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
