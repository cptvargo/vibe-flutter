import '../api/jellyfin_api.dart';

/// A group of genre tags that co-occur in the user's library and therefore
/// represent a coherent musical style (e.g. lofi + chillhop, or
/// christian rap + christian hip-hop + trap).
class GenreCluster {
  final Set<String> genres; // all lowercase-trimmed
  GenreCluster._(this.genres);

  bool containsGenre(String g) => genres.contains(g.toLowerCase().trim());
  bool matchesAny(Iterable<String> gs) => gs.any(containsGenre);

  @override
  String toString() => 'GenreCluster(${genres.join(', ')})';
}

/// Dynamically clusters genre tags by co-occurrence so every genre-aware
/// feature works for any user's library — not just predefined sub-genres.
///
/// How it works:
///   1. Scan all albums in the library and record their genre tags.
///   2. Genres appearing on > 40 % of albums are marked "generic" (e.g.
///      "Music", "Christian") and excluded from clustering — they're too
///      broad to indicate a specific style.
///   3. Union-Find: any two meaningful genres that appear together on the
///      same album are joined into one cluster.
///   4. The result is a list of clusters, each representing a distinct
///      musical style in this user's specific library.
///
/// Results are cached in memory for the session. Call [invalidate] on
/// sign-out or library refresh.
class GenreClusterService {
  static List<GenreCluster>? _clusters;
  static Set<String>? _genericGenres;

  /// Returns cached clusters, building them via a Jellyfin API call if needed.
  static Future<List<GenreCluster>> getClusters() async {
    if (_clusters != null) return _clusters!;
    _build(await JellyfinApi.getAllAlbumsRaw());
    return _clusters!;
  }

  /// Prime the cache from already-fetched album data so the caller avoids
  /// a second API round-trip. No-ops if cache is already warm.
  static void buildFromAlbums(List<Map<String, dynamic>> albums) {
    if (_clusters != null) return;
    _build(albums);
  }

  /// Clear the cache — call this on sign-out or library refresh.
  static void invalidate() {
    _clusters = null;
    _genericGenres = null;
  }

  /// The cluster whose genres overlap [genres], or null if unrecognized.
  static GenreCluster? clusterFor(Set<String> genres) {
    final clusters = _clusters;
    if (clusters == null) return null;
    for (final c in clusters) {
      if (c.matchesAny(genres)) return c;
    }
    return null;
  }

  /// True if [g] is too broad to indicate a musical sub-style in this library.
  static bool isGeneric(String g) =>
      _genericGenres?.contains(g.toLowerCase().trim()) ?? false;

  // ── Internal ────────────────────────────────────────────────────────────────

  static void _build(List<Map<String, dynamic>> albums) {
    final genreFreq      = <String, int>{};
    final albumGenreLists = <List<String>>[];

    for (final album in albums) {
      final genres = ((album['Genres'] as List?) ?? [])
          .cast<String>()
          .map((g) => g.toLowerCase().trim())
          .where((g) => g.isNotEmpty)
          .toList();
      albumGenreLists.add(genres);
      for (final g in genres) { genreFreq[g] = (genreFreq[g] ?? 0) + 1; }
    }

    // Genres on > 40 % of albums AND appearing on at least 3 albums are
    // generic separators (e.g. "music", "christian"), not style markers.
    // We also require at least 3 distinct genres in the library before running
    // generic detection — tiny libraries where one genre dominates naturally
    // are not using junk tags, they just have a focused collection.
    final total = albums.length;
    _genericGenres = (total == 0 || genreFreq.length < 3)
        ? {}
        : genreFreq.entries
            .where((e) => e.value >= 3 && e.value / total > 0.4)
            .map((e) => e.key)
            .toSet();

    // Union-Find: genres that co-occur on an album belong to the same cluster.
    final parent = <String, String>{};

    String find(String x) {
      parent.putIfAbsent(x, () => x);
      if (parent[x] != x) parent[x] = find(parent[x]!);
      return parent[x]!;
    }

    void union(String a, String b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (final genres in albumGenreLists) {
      final meaningful =
          genres.where((g) => !_genericGenres!.contains(g)).toList();
      if (meaningful.isEmpty) continue;
      parent.putIfAbsent(meaningful[0], () => meaningful[0]);
      for (int i = 1; i < meaningful.length; i++) {
        union(meaningful[0], meaningful[i]);
      }
    }

    final clusterMap = <String, Set<String>>{};
    for (final g in parent.keys) {
      clusterMap.putIfAbsent(find(g), () => {}).add(g);
    }

    _clusters = clusterMap.values
        .where((s) => s.isNotEmpty)
        .map((s) => GenreCluster._(Set.unmodifiable(s)))
        .toList();
  }
}
