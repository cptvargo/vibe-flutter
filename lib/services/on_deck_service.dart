import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved album session — enough to show progress in the On Deck grid
/// and to resume exactly where the user left off via Jump Back In.
class AlbumSession {
  final String   albumId;
  final String   albumTitle;
  final String   artist;
  final String   artUrl;
  final int      playedMs;        // cumulative album time played — drives progress bar
  final int      totalMs;         // full album duration — drives progress bar
  final int      trackPositionMs; // seek point within the current track (resume)
  final int      queueIndex;      // track index in album queue (resume)
  final int?     trackNumber;     // Jellyfin IndexNumber, displayed in Jump Back In
  final String   trackTitle;      // displayed in Jump Back In
  final int      trackDurationMs; // track duration for "X:XX left" display
  final DateTime savedAt;

  const AlbumSession({
    required this.albumId,
    required this.albumTitle,
    required this.artist,
    required this.artUrl,
    required this.playedMs,
    required this.totalMs,
    required this.trackPositionMs,
    required this.queueIndex,
    this.trackNumber,
    required this.trackTitle,
    required this.trackDurationMs,
    required this.savedAt,
  });

  double get progressFraction =>
      totalMs > 0 ? (playedMs / totalMs).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
    'albumId':         albumId,
    'albumTitle':      albumTitle,
    'artist':          artist,
    'artUrl':          artUrl,
    'playedMs':        playedMs,
    'totalMs':         totalMs,
    'trackPositionMs': trackPositionMs,
    'queueIndex':      queueIndex,
    'trackNumber':     trackNumber,
    'trackTitle':      trackTitle,
    'trackDurationMs': trackDurationMs,
    'savedAt':         savedAt.millisecondsSinceEpoch,
  };

  factory AlbumSession.fromJson(Map<String, dynamic> j) => AlbumSession(
    albumId:         j['albumId']         as String,
    albumTitle:      j['albumTitle']      as String? ?? '',
    artist:          j['artist']          as String? ?? '',
    artUrl:          j['artUrl']          as String? ?? '',
    playedMs:        j['playedMs']        as int?    ?? 0,
    totalMs:         j['totalMs']         as int?    ?? 0,
    trackPositionMs: j['trackPositionMs'] as int?    ?? 0,
    queueIndex:      j['queueIndex']      as int?    ?? 0,
    trackNumber:     j['trackNumber']     as int?,
    trackTitle:      j['trackTitle']      as String? ?? '',
    trackDurationMs: j['trackDurationMs'] as int?    ?? 0,
    savedAt: DateTime.fromMillisecondsSinceEpoch(j['savedAt'] as int? ?? 0),
  );
}

/// Manages up to [_maxSessions] album sessions for On Deck and Jump Back In.
/// Sessions are persisted to SharedPreferences, keyed by albumId (upsert).
/// Finished albums are removed automatically by the audio handler.
class OnDeckService {
  static const _key         = 'vibe_on_deck_v1';
  static const _maxSessions = 27;

  static final _sessions = <String, AlbumSession>{};

  static final _ctrl = StreamController<void>.broadcast();
  static Stream<void> get updated => _ctrl.stream;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_key);
      if (raw == null) return;
      final list  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _sessions.clear();
      for (final j in list) {
        final s = AlbumSession.fromJson(j);
        _sessions[s.albumId] = s;
      }
    } catch (_) {}
  }

  static Future<void> saveSession({
    required String albumId,
    required String albumTitle,
    required String artist,
    required String artUrl,
    required int    playedMs,
    required int    totalMs,
    required int    trackPositionMs,
    required int    queueIndex,
    required int?   trackNumber,
    required String trackTitle,
    required int    trackDurationMs,
  }) async {
    _sessions[albumId] = AlbumSession(
      albumId:         albumId,
      albumTitle:      albumTitle,
      artist:          artist,
      artUrl:          artUrl,
      playedMs:        playedMs,
      totalMs:         totalMs,
      trackPositionMs: trackPositionMs,
      queueIndex:      queueIndex,
      trackNumber:     trackNumber,
      trackTitle:      trackTitle,
      trackDurationMs: trackDurationMs,
      savedAt:         DateTime.now(),
    );
    await _persist();
    _ctrl.add(null);
  }

  static Future<void> patchAlbumTitle(String albumId, String title) async {
    final s = _sessions[albumId];
    if (s == null || title.isEmpty) return;
    _sessions[albumId] = AlbumSession(
      albumId:         s.albumId,
      albumTitle:      title,
      artist:          s.artist,
      artUrl:          s.artUrl,
      playedMs:        s.playedMs,
      totalMs:         s.totalMs,
      trackPositionMs: s.trackPositionMs,
      queueIndex:      s.queueIndex,
      trackNumber:     s.trackNumber,
      trackTitle:      s.trackTitle,
      trackDurationMs: s.trackDurationMs,
      savedAt:         s.savedAt,
    );
    await _persist();
  }

  static Future<void> removeSession(String albumId) async {
    if (!_sessions.containsKey(albumId)) return;
    _sessions.remove(albumId);
    await _persist();
    _ctrl.add(null);
  }

  static AlbumSession?      getSession(String albumId) => _sessions[albumId];
  static AlbumSession?      getMostRecent()             => getAllSessions().firstOrNull;
  static List<AlbumSession> getAllSessions()             => _sorted();

  static List<AlbumSession> _sorted() => _sessions.values.toList()
    ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  static Future<void> _persist() async {
    try {
      final sorted  = _sorted();
      // Trim in-memory cache
      if (sorted.length > _maxSessions) {
        for (final s in sorted.skip(_maxSessions)) {
          _sessions.remove(s.albumId);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_sorted().map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }
}
