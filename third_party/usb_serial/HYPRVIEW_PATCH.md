Vendored copy of usb_serial 0.5.2 (https://pub.dev/packages/usb_serial,
BSD-3-Clause, see LICENSE) with `android/build.gradle` updated for Android
Gradle Plugin 9 / Gradle 9: the original uses `jcenter()` and an old
buildscript, which no longer build. The Dart and Java code is unchanged.
Remove this copy and the dependency override once upstream is fixed.
