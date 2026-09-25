import 'dart:io';

import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> prepare() async {
  if (!Platform.isAndroid) return;
  // Android 13+ asks for nearby Wi-Fi devices and 16+ for the local
  // network; older versions grant both with the manifest. Discovery still
  // works with known peers if they are refused.
  try {
    await [
      Permission.nearbyWifiDevices,
      Permission.accessLocalNetwork,
    ].request();
  } catch (_) {}
  // Without the lock, Android drops multicast packets (discovery).
  try {
    await FlutterMulticastLock().acquireMulticastLock(lockName: 'lsl');
  } catch (_) {}
}
