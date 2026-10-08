import 'package:peer_coordinator/data.dart' show PeerClock;

import 'lsl_types.dart';

LslBackend createBackend() => _Unsupported();

class _Unsupported implements LslBackend {
  @override
  bool get supported => false;

  @override
  String get version => '';

  @override
  void configure(LslNetworkOptions options) {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> Function()? networkPrep;

  /// A steady clock in place of LSL's (and the one `peer_coordinator`
  /// stamps with, so the two agree where there is no LSL).
  @override
  double clock() => PeerClock.now();

  @override
  LslDiscovery discover() => throw UnsupportedError('LSL is not available');

  @override
  Future<LslInlet> openInlet(
    LslStreamDescription stream,
    LslInletOptions options,
  ) => throw UnsupportedError('LSL is not available');

  @override
  Future<LslOutlet> createOutlet(
    LslOutletSpec spec,
    LslOutletOptions options,
  ) => throw UnsupportedError('LSL is not available');
}
