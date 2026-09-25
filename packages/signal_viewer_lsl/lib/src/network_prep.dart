import 'network_prep_stub.dart'
    if (dart.library.io) 'network_prep_io.dart'
    as platform;

/// What LSL needs before it is first used on this platform (Android: local
/// network permissions and a Wi-Fi multicast lock); nothing elsewhere.
Future<void> lslNetworkPrep() => platform.prepare();
