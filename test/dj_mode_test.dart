import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibe/providers/dj_mode_notifier.dart';

// ── DJ mode state helpers ─────────────────────────────────────────────────────
// Mirrors the setPlaybackMode + _inGap logic in audio_handler.dart so we can
// test state transitions without a real AudioPlayer or audio session.

// Simulates the mode-switch guard: returns true if the engine should
// immediately advance to the next track when switching out of gap mode.
bool shouldAdvanceOnModeSwitch({required bool wasInGap, required bool newDjModeOn}) {
  return wasInGap && newDjModeOn;
}

// Simulates the gap-cancel conditions: returns whether the gap should be
// cancelled for each user action.
bool gapCancelledByAction(String action) {
  const cancelActions = {'pause', 'stop', 'skipNext', 'skipPrev', 'skipToItem', 'playTracks'};
  return cancelActions.contains(action);
}

void main() {
  // ── DjModeNotifier ──────────────────────────────────────────────────────────

  group('DjModeNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('initialises to true (DJ mode on / crossfade)', () {
      final notifier = DjModeNotifier((_) {});
      expect(notifier.state, isTrue);
    });

    test('toggle flips state from true to false', () async {
      final notifier = DjModeNotifier((_) {});
      await notifier.toggle();
      expect(notifier.state, isFalse);
    });

    test('toggle flips state back to true', () async {
      final notifier = DjModeNotifier((_) {});
      await notifier.toggle(); // → false
      await notifier.toggle(); // → true
      expect(notifier.state, isTrue);
    });

    test('toggle persists false to SharedPreferences', () async {
      final notifier = DjModeNotifier((_) {});
      await notifier.toggle(); // → false
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('vibe_dj_mode_v1'), isFalse);
    });

    test('toggle persists true to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'vibe_dj_mode_v1': false});
      final notifier = DjModeNotifier((_) {});
      // Wait for async _load() to settle
      await Future<void>.delayed(Duration.zero);
      await notifier.toggle(); // false → true
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('vibe_dj_mode_v1'), isTrue);
    });

    test('_load() restores saved false from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'vibe_dj_mode_v1': false});
      final calls = <bool>[];
      final notifier = DjModeNotifier(calls.add);
      await Future<void>.delayed(Duration.zero); // let _load() complete
      expect(notifier.state, isFalse);
      // Callback fired once to sync the handler
      expect(calls, [false]);
    });

    test('_load() is a no-op when saved value matches default (true)', () async {
      SharedPreferences.setMockInitialValues({'vibe_dj_mode_v1': true});
      final calls = <bool>[];
      final notifier = DjModeNotifier(calls.add);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state, isTrue);
      // No callback fired — state unchanged
      expect(calls, isEmpty);
    });

    test('callback fires immediately on toggle', () async {
      final calls = <bool>[];
      final notifier = DjModeNotifier(calls.add);
      await notifier.toggle();
      expect(calls, [false]);
    });

    test('callback fires with correct value on each toggle', () async {
      final calls = <bool>[];
      final notifier = DjModeNotifier(calls.add);
      await notifier.toggle(); // → false
      await notifier.toggle(); // → true
      expect(calls, [false, true]);
    });
  });

  // ── Gap mode state-machine logic ────────────────────────────────────────────

  group('shouldAdvanceOnModeSwitch', () {
    test('advances when switching to crossfade while in gap', () {
      expect(
        shouldAdvanceOnModeSwitch(wasInGap: true, newDjModeOn: true),
        isTrue,
      );
    });

    test('no advance when not in gap', () {
      expect(
        shouldAdvanceOnModeSwitch(wasInGap: false, newDjModeOn: true),
        isFalse,
      );
    });

    test('no advance when switching to gap mode (DJ off)', () {
      expect(
        shouldAdvanceOnModeSwitch(wasInGap: true, newDjModeOn: false),
        isFalse,
      );
    });
  });

  group('gapCancelledByAction', () {
    test('pause cancels gap', () => expect(gapCancelledByAction('pause'), isTrue));
    test('stop cancels gap',  () => expect(gapCancelledByAction('stop'),  isTrue));
    test('skipNext cancels gap',    () => expect(gapCancelledByAction('skipNext'),    isTrue));
    test('skipPrev cancels gap',    () => expect(gapCancelledByAction('skipPrev'),    isTrue));
    test('skipToItem cancels gap',  () => expect(gapCancelledByAction('skipToItem'),  isTrue));
    test('playTracks cancels gap',  () => expect(gapCancelledByAction('playTracks'),  isTrue));
    test('unrelated action does not cancel gap', () {
      expect(gapCancelledByAction('positionTick'), isFalse);
    });
  });
}
