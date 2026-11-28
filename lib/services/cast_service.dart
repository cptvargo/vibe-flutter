import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../api/jellyfin_api.dart';
import 'cast_server.dart';
import 'download_service.dart';

enum CastState { idle, discovering, connecting, connected }

class CastDevice {
  final String id;
  final String name;
  final String model;
  const CastDevice({required this.id, required this.name, required this.model});
}

// CastService wraps the native Google Cast SDK via platform channels.
//
// Channel contract (vibe/cast MethodChannel):
//   startDiscovery()
//   connectToDevice({deviceId: String})
//   loadMedia({url, title, artist, album, artUrl, contentType})
//   stopCasting()
//   seekTo({positionMs: int})
//
// Events (vibe/cast/events EventChannel):
//   {type: "devicesUpdated", devices: [{id, name, model}]}
//   {type: "sessionStarted", device: {id, name, model}}
//   {type: "sessionEnded"}
//   {type: "sessionFailed", error: String}
class CastService extends ChangeNotifier {
  static const _ch  = MethodChannel('vibe/cast');
  static const _evt = EventChannel('vibe/cast/events');

  CastState        _state   = CastState.idle;
  List<CastDevice> _devices = [];
  CastDevice?      _current;
  StreamSubscription<dynamic>? _sub;
  String?          _loadedTrackId;
  MediaItem?       _pendingItem;    // queued while connecting; loaded on sessionStarted
  VoidCallback?    _resumeCallback; // called if session fails, to undo a local pause

  CastState        get state          => _state;
  List<CastDevice> get devices        => _devices;
  CastDevice?      get current        => _current;
  bool             get isConnected    => _state == CastState.connected;
  String?          get loadedTrackId  => _loadedTrackId;

  // Set before calling connectToDevice. Called automatically if the session
  // fails, so local playback can be restored after an interrupted pause.
  set resumeCallback(VoidCallback? cb) => _resumeCallback = cb;

  CastService() {
    _startListening();
    // Begin discovery immediately so devices are ready before the user opens
    // the Cast sheet.
    startDiscovery();
  }

  void _startListening() {
    try {
      _sub = _evt.receiveBroadcastStream().listen(
        (raw) {
          if (raw is! Map) return;
          _onEvent(Map<String, dynamic>.from(raw));
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type'] as String? ?? '') {
      case 'devicesUpdated':
        _devices = ((e['devices'] as List?) ?? [])
            .cast<Map>()
            .map((d) => CastDevice(
                  id:    d['id']    as String? ?? '',
                  name:  d['name']  as String? ?? 'Unknown',
                  model: d['model'] as String? ?? '',
                ))
            .toList();
        notifyListeners();
      case 'sessionStarted':
        final d = e['device'] as Map?;
        _current = d == null ? null : CastDevice(
          id:    d['id']    as String? ?? '',
          name:  d['name']  as String? ?? 'Unknown',
          model: d['model'] as String? ?? '',
        );
        _state = CastState.connected;
        _resumeCallback = null; // committed — no need to undo the local pause
        notifyListeners();
        // Load any media that was requested before the session was established.
        if (_pendingItem != null) {
          final item = _pendingItem!;
          _pendingItem = null;
          loadMedia(item);
        }
      case 'sessionEnded':
        _current        = null;
        _loadedTrackId  = null;
        _pendingItem    = null;
        _resumeCallback = null; // session ended normally; don't undo a past pause
        _state          = CastState.discovering;
        CastServer.stop();
        notifyListeners();
      case 'sessionFailed':
        _current     = null;
        _pendingItem = null;
        _state       = CastState.discovering;
        notifyListeners();
        _resumeCallback?.call(); // restore local playback if we paused it
        _resumeCallback = null;
    }
  }

  Future<void> startDiscovery() async {
    if (_state == CastState.discovering || _state == CastState.connected) return;
    _state = CastState.discovering;
    notifyListeners();
    try { await _ch.invokeMethod<void>('startDiscovery'); } catch (_) {}
  }

  Future<void> connectToDevice(CastDevice device) async {
    _state = CastState.connecting;
    notifyListeners();
    try {
      await _ch.invokeMethod<void>('connectToDevice', {'deviceId': device.id});
    } catch (_) {
      _state = CastState.discovering;
      notifyListeners();
    }
  }

  // Load [item] on the active Cast session.
  // If called while still connecting, the item is queued and loaded
  // automatically once sessionStarted fires.
  // For offline tracks starts the local HTTP server and serves the file over
  // WiFi; for online tracks the Cast receiver fetches directly from Jellyfin.
  Future<void> loadMedia(MediaItem item) async {
    if (!isConnected) {
      _pendingItem = item; // will be loaded on sessionStarted
      return;
    }

    final trackId   = item.id;
    final isOffline = DownloadService.isDownloaded(trackId);
    String mediaUrl;
    String contentType = 'audio/mpeg';

    if (isOffline) {
      final ok = await CastServer.ensureRunning();
      final localUrl = CastServer.trackUrl(trackId);
      if (ok && localUrl != null) {
        mediaUrl = localUrl;
        // Derive content type from the stored file extension
        final stored = DownloadService.localPathSync(trackId) ?? '';
        final ext    = stored.split('.').last.toLowerCase();
        contentType  = switch (ext) {
          'flac' => 'audio/flac',
          'm4a'  => 'audio/mp4',
          'aac'  => 'audio/aac',
          _      => 'audio/mpeg',
        };
      } else {
        // CastServer couldn't start (e.g. no WiFi) — fall back to Jellyfin stream
        mediaUrl = JellyfinApi.streamUrl(trackId);
      }
    } else {
      mediaUrl = JellyfinApi.streamUrl(trackId);
    }

    final artUrl = (item.extras?['artworkHttpsUrl'] as String?)
        ?? item.artUri?.toString()
        ?? '';

    try {
      await _ch.invokeMethod<void>('loadMedia', {
        'url':         mediaUrl,
        'title':       item.title,
        'artist':      item.artist  ?? '',
        'album':       item.album   ?? '',
        'artUrl':      artUrl,
        'contentType': contentType,
        'trackId':     trackId,
      });
      _loadedTrackId = trackId;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopCasting() async {
    try { await _ch.invokeMethod<void>('stopCasting'); } catch (_) {}
    await CastServer.stop();
    _current        = null;
    _loadedTrackId  = null;
    _pendingItem    = null;
    _resumeCallback = null; // explicit user action — don't auto-resume
    _state          = CastState.discovering;
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    if (!isConnected) return;
    try {
      await _ch.invokeMethod<void>('seekTo',
          {'positionMs': position.inMilliseconds});
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
