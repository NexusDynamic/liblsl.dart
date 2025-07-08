import 'package:test/test.dart';

// Import all test suites
import 'high_frequency_transport_test.dart' as transport_tests;
import 'integration_test.dart' as integration_tests;
import 'isolate_separation_test.dart' as isolate_tests;
import 'performance_test.dart' as performance_tests;

void main() {
  group('LibLSL Coordinator Package Tests', () {
    group('High Frequency Transport Tests', transport_tests.main);
    group('Integration Tests', integration_tests.main);
    group('Isolate Separation Tests', isolate_tests.main);
    group('Performance Tests', performance_tests.main);
  });
}
