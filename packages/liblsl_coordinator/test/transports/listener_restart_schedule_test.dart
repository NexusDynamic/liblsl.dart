import 'package:liblsl_coordinator/transports/lsl/isolate/listener_restart_schedule.dart';
import 'package:liblsl_coordinator/transports/lsl/lsl_transport.dart';
import 'package:test/test.dart';

/// The policy behind restarting an event-driven inlet's sample listener.
///
/// A listener that ended by itself used to leave its inlet open, its peer
/// registered and nothing reading either, with at most one line in the log.
/// What happens next is decided here, network-free, because a listener cannot
/// be made to die on demand.
void main() {
  const ms = Duration(milliseconds: 1);

  group('backoff', () {
    test('the first restart is prompt and each further one waits longer', () {
      final s = ListenerRestartSchedule();
      expect(s.noteFailure('peer'), ms * 100);
      expect(s.noteFailure('peer'), ms * 200);
      expect(s.noteFailure('peer'), ms * 400);
      expect(s.failuresFor('peer'), 3);
    });

    test('the delay is capped, so a listener is retried forever', () {
      final s = ListenerRestartSchedule(maxDelay: const Duration(seconds: 2));
      for (var i = 0; i < 200; i++) {
        final delay = s.noteFailure('dead');
        expect(delay, greaterThan(Duration.zero));
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 2)));
      }
      expect(s.noteFailure('dead'), const Duration(seconds: 2));
    });

    test('peers are counted separately', () {
      final s = ListenerRestartSchedule();
      s.noteFailure('a');
      s.noteFailure('a');
      expect(s.noteFailure('b'), ms * 100);
      expect(s.failuresFor('a'), 2);
    });
  });

  group('recovery', () {
    test('a healthy listener starts over, and says it had been failing', () {
      final s = ListenerRestartSchedule();
      s.noteFailure('peer');
      s.noteFailure('peer');
      expect(s.noteHealthy('peer'), isTrue);
      expect(s.failuresFor('peer'), 0);
      expect(s.noteFailure('peer'), ms * 100);
    });

    test('a listener that never failed has nothing to recover from', () {
      expect(ListenerRestartSchedule().noteHealthy('peer'), isFalse);
    });

    test('a removed inlet leaves nothing behind', () {
      final s = ListenerRestartSchedule();
      s.noteFailure('gone');
      s.forget('gone');
      expect(s.failuresFor('gone'), 0);
      expect(s.noteHealthy('gone'), isFalse);
    });
  });

  group('reopening the inlet', () {
    test('only once restarting the listener has kept failing', () {
      final s = ListenerRestartSchedule(reopenAfter: 3);
      s.noteFailure('peer');
      expect(s.shouldReopenInlet('peer'), isFalse);
      s.noteFailure('peer');
      expect(s.shouldReopenInlet('peer'), isFalse);
      s.noteFailure('peer');
      expect(s.shouldReopenInlet('peer'), isTrue);
      s.noteFailure('peer');
      expect(s.shouldReopenInlet('peer'), isTrue);
    });

    test('at once when liblsl says the stream is lost', () {
      final s = ListenerRestartSchedule();
      s.noteFailure('peer');
      expect(s.shouldReopenInlet('peer', errorCode: -2), isTrue);
      expect(s.shouldReopenInlet('peer', errorCode: -4), isFalse);
    });
  });

  group('LSLTransportConfig.restartFailedListeners', () {
    test('is on unless turned off', () {
      expect(LSLTransportConfig().restartFailedListeners, isTrue);
      expect(
        LSLTransportConfigFactory().fromMap({}).restartFailedListeners,
        isTrue,
      );
    });

    test('survives a round trip and a copy', () {
      final off = LSLTransportConfig(restartFailedListeners: false);
      final restored = LSLTransportConfigFactory().fromMap(off.toMap());
      expect(restored.restartFailedListeners, isFalse);
      expect(restored, off);
      expect(off, isNot(LSLTransportConfig()));
      expect(off.copyWith().restartFailedListeners, isFalse);
      expect(
        off.copyWith(restartFailedListeners: true).restartFailedListeners,
        isTrue,
      );
    });
  });
}
