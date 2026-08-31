import 'dart:async';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../api/jellyfin_api.dart';
import '../api/jellyfin_models.dart';

class DownloadService {
  static const _boxName = 'vibe_downloads_v1';
  static Box<Map>? _box;
  static String?   _dir;

  static final _active     = <String, double>{};
  static final _activeInfo = <String, (String title, String artist)>{};
  static final _errors     = <String, String>{};

  static final _onChange = StreamController<void>.broadcast();
  static Stream<void> get onChange => _onChange.stream;

  // Persistent HTTP client — reuses TCP connections across all parallel downloads.
  static final _httpClient = HttpClient()
    ..autoUncompress = false
    ..idleTimeout = const Duration(seconds: 60);

  static Future<void> init() async {
    _box = await Hive.openBox<Map>(_boxName);
    final docDir = await getApplicationDocumentsDirectory();
    _dir = '${docDir.path}/vibe_downloads';
    await Directory(_dir!).create(recursive: true);
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  static bool   isDownloaded(String id)  => _box?.containsKey(id) == true;
  static bool   isDownloading(String id) => _active.containsKey(id);
  static double progress(String id)      => _active[id] ?? 0.0;
  static String? errorFor(String id)     => _errors[id];

  static bool get hasActiveDownloads => _active.isNotEmpty;
  static int  get activeCount        => _active.length;
  static List<String> get activeItemIds => _active.keys.toList();

  static (String title, String artist)? activeInfo(String id) => _activeInfo[id];

  // ── Data access ───────────────────────────────────────────────────────────

  static Map<String, dynamic>? getDownloadData(String id) {
    final raw = _box?.get(id);
    return raw != null ? Map<String, dynamic>.from(raw) : null;
  }

  // All downloads sorted newest-first (for the flat list view only).
  static List<Map<String, dynamic>> getDownloads() {
    return (_box?.values ?? [])
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
      ..sort((a, b) {
        final ad = a['downloadedAt'] as String? ?? '';
        final bd = b['downloadedAt'] as String? ?? '';
        return bd.compareTo(ad);
      });
  }

  // Synchronous lookup used by the audio handler at play time.
  static String? localPathSync(String id) {
    final data = _box?.get(id);
    return data != null ? data['filePath'] as String? : null;
  }

  static VibeTrack trackFromData(Map<String, dynamic> data) => VibeTrack(
    id:          data['itemId']    as String,
    url:         Uri.file(data['filePath'] as String).toString(),
    title:       data['title']    as String? ?? '',
    artist:      data['artist']   as String? ?? '',
    album:       data['album']    as String? ?? '',
    albumId:     data['albumId']  as String?,
    artistId:    data['artistId'] as String?,
    artworkUrl:  data['artworkUrl'] as String? ?? '',
    colorUrl:    data['colorUrl']   as String? ?? '',
    blurHash:    data['blurHash']   as String?,
    duration:    Duration(microseconds: data['durationMicros'] as int? ?? 0),
    raw:         {},
  );

  // Patch stored metadata without touching the audio file.
  static Future<void> updateTrackMetadata(String id, Map<String, dynamic> updates) async {
    final existing = _box?.get(id);
    if (existing == null) return;
    await _box?.put(id, {...Map<String, dynamic>.from(existing), ...updates});
  }

  // ── Storage ───────────────────────────────────────────────────────────────

  static Future<int> storageUsedBytes() async {
    int total = 0;
    for (final data in getDownloads()) {
      final path = data['filePath'] as String?;
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) total += await f.length();
        } catch (_) {}
      }
    }
    return total;
  }

  // ── Download ──────────────────────────────────────────────────────────────

  static Future<void> downloadTrack(VibeTrack track, {int fallbackPosition = 0}) async {
    if (isDownloaded(track.id) || isDownloading(track.id)) return;

    _active[track.id]     = 0.0;
    _activeInfo[track.id] = (track.title, track.artist);
    _errors.remove(track.id);
    _onChange.add(null);

    final path = '${_dir!}/${track.id}.audio';
    try {
      // Use the stream URL (same as playback) — it needs no special Download
      // permission and never redirects. Add the Emby auth header because some
      // Jellyfin versions reject api_key-only requests on certain endpoints.
      final req = await _httpClient.getUrl(Uri.parse(JellyfinApi.streamUrl(track.id)));
      req.headers.add('X-Emby-Authorization', JellyfinApi.authHeader);
      final res = await req.close();

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode} for track ${track.id}');
      }

      final total    = res.contentLength;
      int   received = 0;

      final sink = File(path).openWrite();
      double lastNotified = 0.0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = received / total;
          if (p - lastNotified >= 0.01 || p >= 1.0) {
            lastNotified = p;
            _active[track.id] = p;
            _onChange.add(null);
          }
        }
      }
      await sink.flush();
      await sink.close();

      // Disc + track numbers come from Jellyfin metadata (raw), which is
      // populated when the track was fetched from the album screen.
      // fallbackPosition is only used when raw is empty (should never happen
      // for normal album downloads, but guards against future edge cases).
      final discNumber  = track.raw['ParentIndexNumber'] as int? ?? 1;
      final trackNumber = track.raw['IndexNumber']       as int? ?? fallbackPosition;

      await _box?.put(track.id, {
        'itemId':        track.id,
        'title':         track.title,
        'artist':        track.artist,
        'album':         track.album,
        'albumId':       track.albumId,
        'artistId':      track.artistId,
        'artworkUrl':    track.artworkUrl,
        'colorUrl':      track.colorUrl,
        'blurHash':      track.blurHash,
        'filePath':      path,
        'durationMicros': track.duration.inMicroseconds,
        'discNumber':    discNumber,
        'trackNumber':   trackNumber,
        'downloadedAt':  DateTime.now().toIso8601String(),
      });

      _active.remove(track.id);
      _activeInfo.remove(track.id);
      _onChange.add(null);
    } catch (e) {
      _active.remove(track.id);
      _activeInfo.remove(track.id);
      _errors[track.id] = e.toString();
      _onChange.add(null);
      try { await File(path).delete(); } catch (_) {}
    }
  }

  // Fire-and-forget parallel downloader.
  // Note: download ORDER does not affect playback order.
  // disc/trackNumber come from Jellyfin metadata on the VibeTrack, not from
  // which track happens to finish first.
  static void downloadTracks(List<VibeTrack> tracks, {int concurrency = 6}) {
    Future(() async {
      int idx = 0;
      Future<void> worker() async {
        while (true) {
          final i = idx++;
          if (i >= tracks.length) break;
          await downloadTrack(tracks[i], fallbackPosition: i);
        }
      }
      final slots = List.generate(
        concurrency.clamp(1, tracks.length),
        (_) => worker(),
      );
      await Future.wait(slots);
    });
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteDownload(String id) async {
    final data = _box?.get(id);
    if (data != null) {
      final path = data['filePath'] as String?;
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
    await _box?.delete(id);
    _onChange.add(null);
  }
}
