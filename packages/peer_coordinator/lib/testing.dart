/// Cross-transport conformance scenarios.
///
/// A transport is only correct if it behaves like every other one, so the
/// scenarios live here rather than in any single package's tests. Implement
/// [ParticipationHarness] for your backend and call the runner; the
/// assertions are identical for in-memory, WebSocket and LSL.
///
/// This library imports `package:test` and is only for use from test files.
library;

export 'src/testing/participation_scenarios.dart';
