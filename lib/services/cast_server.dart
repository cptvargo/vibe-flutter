import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'download_service.dart';

// Local HTTP server that serves downloaded tracks to Cast receivers.
// Cast devices can only load media from URLs, not local file paths — this
// server bridges the gap by exposing each downloaded file over HTTP on the
// phone's local WiFi address. It stays up as long as a Cast session is live
// and handles range requests so the receiver can seek within a track.
class CastServer {
  static HttpServer? _server;
  static String?     _localIp;
  static int         _port = 0;

  static bool    get isRunning => _server != null;
  static int     get port      => _port;
  static String? get localIp   => _localIp;

  static String? trackUrl(String trackId) {
    if (_localIp == null || _port == 0) return null;
    return 'http://$_localIp:$_port/track/$trackId';
  }

  /// Start the server if not already running. Returns true on success.
  static Future<bool> ensureRunning() async {
    if (_server != null) return true;
    _localIp = await _findLocalIp();
    if (_localIp == null) return false;
    try {
      _server = await shelf_io.serve(_handle, '0.0.0.0', 0);
      _port   = _server!.port;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server  = null;
    _port    = 0;
    _localIp = null;
  }

  static Future<Response> _handle(Request req) async {
    final segs = req.url.pathSegments;
    if (segs.length < 2 || segs[0] != 'track') {
      return Response.notFound('Not found');
    }
    final trackId = segs[1];
    final path    = DownloadService.localPathSync(trackId);
    if (path == null) return Response.notFound('Track not found');

    final file = File(path);
    if (!await file.exists()) return Response.notFound('File missing');

    final fileSize   = await file.length();
    final mime       = _mime(path);
    final rangeHeader = req.headers['range'];

    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (m != null) {
        final start  = int.tryParse(m.group(1) ?? '') ?? 0;
        final end    = int.tryParse(m.group(2) ?? '') ?? (fileSize - 1);
        final length = end - start + 1;
        return Response(
          206,
          body: file.openRead(start, end + 1),
          headers: {
            'content-type':   mime,
            'content-range':  'bytes $start-$end/$fileSize',
            'content-length': '$length',
            'accept-ranges':  'bytes',
          },
        );
      }
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'content-type':   mime,
        'content-length': '$fileSize',
        'accept-ranges':  'bytes',
      },
    );
  }

  static String _mime(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3'  => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a'  => 'audio/mp4',
      'aac'  => 'audio/aac',
      'ogg'  => 'audio/ogg',
      'wav'  => 'audio/wav',
      _      => 'audio/mpeg',
    };
  }

  static Future<String?> _findLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.')      ||
              _is172Private(ip)) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _is172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final b = int.tryParse(parts[1]) ?? 0;
    return ip.startsWith('172.') && b >= 16 && b <= 31;
  }
}
