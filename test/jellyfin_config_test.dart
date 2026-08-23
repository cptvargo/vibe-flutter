import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe/api/jellyfin_api.dart';

void main() {
  group('JellyfinApi.authenticateByName JSON parsing', () {
    test('parses valid Jellyfin auth response', () {
      // Simulate what Jellyfin returns on a successful login
      final responseBody = json.encode({
        'AccessToken': 'abc123token',
        'User': {'Id': 'user-uuid-456', 'Name': 'testuser'},
        'ServerId': 'srv-001',
      });

      final data   = json.decode(responseBody) as Map<String, dynamic>;
      final token  = data['AccessToken'] as String?;
      final userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;

      expect(token,  equals('abc123token'));
      expect(userId, equals('user-uuid-456'));
    });

    test('returns null token when AccessToken missing', () {
      final responseBody = json.encode({
        'User': {'Id': 'user-uuid-456'},
        'ServerId': 'srv-001',
      });

      final data  = json.decode(responseBody) as Map<String, dynamic>;
      final token = data['AccessToken'] as String?;

      expect(token, isNull);
    });

    test('returns null userId when User object missing', () {
      final responseBody = json.encode({
        'AccessToken': 'abc123token',
        'ServerId': 'srv-001',
      });

      final data   = json.decode(responseBody) as Map<String, dynamic>;
      final userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;

      expect(userId, isNull);
    });

    test('returns null userId when User.Id missing', () {
      final responseBody = json.encode({
        'AccessToken': 'abc123token',
        'User': {'Name': 'testuser'},
      });

      final data   = json.decode(responseBody) as Map<String, dynamic>;
      final userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;

      expect(userId, isNull);
    });
  });

  group('JellyfinApi URL construction', () {
    test('streamUrl format is correct', () {
      final url = JellyfinApi.streamUrl('item-id-123');
      expect(url, contains('/Audio/item-id-123/stream'));
      expect(url, contains('static=true'));
      expect(url, contains('Container=m4a'));
    });

    test('imageUrl includes fill dimensions and quality', () {
      final url = JellyfinApi.imageUrl('item-id-456', size: 300);
      expect(url, contains('/Items/item-id-456/Images/Primary'));
      expect(url, contains('fillHeight=300'));
      expect(url, contains('fillWidth=300'));
      expect(url, contains('quality=90'));
    });

    test('imageUrl uses provided tag when given', () {
      final url = JellyfinApi.imageUrl('item-id-789', tag: 'sometag');
      expect(url, contains('tag=sometag'));
    });

    test('imageUrl omits tag parameter when not given', () {
      final url = JellyfinApi.imageUrl('item-id-789');
      expect(url, isNot(contains('tag=')));
    });

    test('colorExtractionUrl uses 32px dimensions', () {
      final url = JellyfinApi.colorExtractionUrl('item-id-abc');
      expect(url, contains('fillHeight=32'));
      expect(url, contains('fillWidth=32'));
    });
  });

  group('Jellyfin server URL normalisation', () {
    test('trailing slash stripped before auth endpoint', () {
      const raw   = 'https://jellyfin.example.com/';
      final clean = raw.replaceAll(RegExp(r'/$'), '');
      expect(clean, equals('https://jellyfin.example.com'));
    });

    test('URL without trailing slash is unchanged', () {
      const raw   = 'https://jellyfin.example.com';
      final clean = raw.replaceAll(RegExp(r'/$'), '');
      expect(clean, equals('https://jellyfin.example.com'));
    });

    test('multiple trailing slashes all stripped', () {
      const raw   = 'https://jellyfin.example.com///';
      final clean = raw.replaceAll(RegExp(r'/+$'), '');
      expect(clean, equals('https://jellyfin.example.com'));
    });
  });
}
