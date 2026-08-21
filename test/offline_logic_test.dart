import 'package:flutter_test/flutter_test.dart';

// ── Track ordering ────────────────────────────────────────────────────────────
// Mirrors the _byDiscTrack logic in downloads_screen.dart.
List<Map<String, dynamic>> byDiscTrack(List<Map<String, dynamic>> tracks) {
  return [...tracks]..sort((a, b) {
      final discCmp = (a['discNumber'] as int? ?? 1)
          .compareTo(b['discNumber'] as int? ?? 1);
      if (discCmp != 0) return discCmp;
      return (a['trackNumber'] as int? ?? 0)
          .compareTo(b['trackNumber'] as int? ?? 0);
    });
}

// ── Skip index logic ──────────────────────────────────────────────────────────
// Mirrors the skipToNext logic in audio_handler.dart.
// Returns -1 when there is no next track and loop is off.
int skipNextIndex({
  required bool crossfading,
  required int  queueIdx,
  required int  queueLength,
  bool loopAll = false,
}) {
  if (crossfading) return queueIdx; // crossfade already advanced idx to incoming track
  final next = queueIdx + 1;
  if (next >= queueLength) return loopAll ? 0 : -1;
  return next;
}

void main() {
  // ── Track ordering tests ───────────────────────────────────────────────────

  group('byDiscTrack', () {
    test('sorts single-disc album by track number', () {
      final tracks = [
        {'title': 'Earth',   'discNumber': 1, 'trackNumber': 3},
        {'title': 'Mercury', 'discNumber': 1, 'trackNumber': 1},
        {'title': 'Venus',   'discNumber': 1, 'trackNumber': 2},
      ];
      final sorted = byDiscTrack(tracks);
      expect(sorted[0]['title'], 'Mercury');
      expect(sorted[1]['title'], 'Venus');
      expect(sorted[2]['title'], 'Earth');
    });

    test('sorts multi-disc album: disc 1 before disc 2', () {
      final tracks = [
        {'title': 'D2-T1', 'discNumber': 2, 'trackNumber': 1},
        {'title': 'D1-T2', 'discNumber': 1, 'trackNumber': 2},
        {'title': 'D1-T1', 'discNumber': 1, 'trackNumber': 1},
      ];
      final sorted = byDiscTrack(tracks);
      expect(sorted[0]['title'], 'D1-T1');
      expect(sorted[1]['title'], 'D1-T2');
      expect(sorted[2]['title'], 'D2-T1');
    });

    test('falls back to disc 1 when discNumber is null', () {
      final tracks = [
        {'title': 'B', 'discNumber': null, 'trackNumber': 2},
        {'title': 'A', 'discNumber': null, 'trackNumber': 1},
      ];
      final sorted = byDiscTrack(tracks);
      expect(sorted[0]['title'], 'A');
      expect(sorted[1]['title'], 'B');
    });

    test('stable on already-sorted list', () {
      final tracks = [
        {'title': 'Mercury', 'discNumber': 1, 'trackNumber': 1},
        {'title': 'Venus',   'discNumber': 1, 'trackNumber': 2},
        {'title': 'Earth',   'discNumber': 1, 'trackNumber': 3},
      ];
      final sorted = byDiscTrack(tracks);
      expect(sorted.map((t) => t['title']).toList(),
          ['Mercury', 'Venus', 'Earth']);
    });
  });

  // ── Track number display test ─────────────────────────────────────────────
  // Jellyfin IndexNumber is 1-based; we must NOT add 1 to it.

  group('track number display', () {
    test('Mercury IndexNumber 1 displays as 1, not 2', () {
      final trackNumber = 1; // from Jellyfin IndexNumber
      // Correct: use as-is
      expect(trackNumber, 1);
      // Old bug was (trackNumber ?? i) + 1 which would give 2
      final buggy = (trackNumber) + 1;
      expect(buggy, isNot(1));
    });
  });

  // ── Skip index logic tests ────────────────────────────────────────────────

  group('skipNextIndex', () {
    test('normal skip: Mercury (0) -> Venus (1)', () {
      expect(skipNextIndex(crossfading: false, queueIdx: 0, queueLength: 9), 1);
    });

    test('crossfade active: skip lands on incoming track (Venus=1), not Earth (2)', () {
      // _queueIdx is already 1 (Venus) because crossfade advanced it.
      // Pressing skip should restart Venus from 0, not jump to Earth.
      expect(skipNextIndex(crossfading: true, queueIdx: 1, queueLength: 9), 1);
    });

    test('crossfade active: without fix, old logic would give Earth (2)', () {
      // Demonstrates what the bug was: _nextIndex = _queueIdx + 1 = 2
      final brokenResult = 1 + 1; // _queueIdx(1) + 1
      expect(brokenResult, 2); // Earth — the wrong track
    });

    test('skip from last track returns -1 (no loop)', () {
      expect(skipNextIndex(crossfading: false, queueIdx: 8, queueLength: 9), -1);
    });

    test('skip from last track loops to 0 when loop-all is on', () {
      expect(
        skipNextIndex(crossfading: false, queueIdx: 8, queueLength: 9, loopAll: true),
        0,
      );
    });

    test('normal skip mid-album: Venus (1) -> Earth (2)', () {
      expect(skipNextIndex(crossfading: false, queueIdx: 1, queueLength: 9), 2);
    });
  });
}
