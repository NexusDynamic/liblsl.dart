import 'package:liblsl/lsl.dart';

/// Test-specific LSL configuration with optimized settings for concurrent tests
class TestLSLConfig {
  static LSLApiConfig createTestConfig() {
    return LSLApiConfig(
      // Disable IPv6 for faster resolution
      ipv6: IPv6Mode.disable,

      // Faster stream expiry - streams expire in 0.5 seconds instead of default (15s)
      // This helps with cleanup between tests
      watchdogTimeThreshold: 0.5, // Expire streams in 0.5 seconds
      watchdogCheckInterval: 0.1, // Check every 100ms
      // Much larger port range for concurrent tests
      // Default is usually 32 ports starting at 16572
      // We'll use 1000 ports to handle many concurrent streams
      basePort: 17000, // Start higher to avoid conflicts
      portRange: 1000, // 17000-18000 gives us 1000 ports -> 500 streams
      multicastPort: 16571, // Keep standard multicast port
      // Faster continuous resolve for quicker discovery/cleanup
      continuousResolveInterval:
          0.1, // Check for new streams every 100ms instead of 500ms
      // Faster multicast settings
      multicastMinRTT: 0.01, // Faster minimum RTT
      multicastMaxRTT: 0.1, // Shorter maximum RTT for faster cleanup
      // Smaller buffer reserves for testing
      outletBufferReserveMs: 1000, // 1 second instead of 5
      inletBufferReserveMs: 1000, // 1 second instead of 5
    );
  }

  /// Initialize LSL with test configuration
  /// Must be called before any LSL operations
  static void initializeForTesting() {
    LSL.setConfigContent(createTestConfig());
  }
}
