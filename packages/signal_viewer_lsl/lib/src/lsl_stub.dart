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
  double clock() => DateTime.now().microsecondsSinceEpoch / 1e6;

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
