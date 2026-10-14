import 'package:liblsl_coordinator/transports/lsl/lsl_transport.dart';
import 'package:test/test.dart';

void main() {
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
