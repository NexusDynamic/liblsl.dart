# android_multicast_lock

A Flutter plugin for managing Android WiFi multicast locks. This plugin allows you to acquire and release multicast locks on Android devices, which is necessary for receiving multicast UDP packets.

## Features

- ✅ Acquire WiFi multicast locks on Android
- ✅ Release WiFi multicast locks on Android  
- ✅ Check if multicast lock is currently held
- ✅ Cross-platform compatible (no-op on iOS/other platforms)
- ✅ Automatic permission handling

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  android_multicast_lock: ^1.0.0
```

## Android Setup

The plugin automatically includes the required Android permission. No additional setup is needed.

However, if you want to explicitly declare the permission in your app's `android/app/src/main/AndroidManifest.xml`, add:

```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```

## Usage

```dart
import 'package:android_multicast_lock/android_multicast_lock.dart';

final androidMulticastLock = AndroidMulticastLock();

// Acquire the multicast lock
await androidMulticastLock.acquireMulticastLock();

// Check if lock is held
bool isHeld = await androidMulticastLock.isMulticastLockHeld();
print('Multicast lock held: $isHeld');

// Release the multicast lock
await androidMulticastLock.releaseMulticastLock();
```

## API Reference

### `acquireMulticastLock()`

Acquires the WiFi multicast lock. This allows the device to receive multicast UDP packets.

**Returns:** `Future<void>`

**Throws:** `PlatformException` if the lock cannot be acquired.

### `releaseMulticastLock()`

Releases the WiFi multicast lock.

**Returns:** `Future<void>`

**Throws:** `PlatformException` if the lock cannot be released.

### `isMulticastLockHeld()`

Checks whether the multicast lock is currently held.

**Returns:** `Future<bool>` - `true` if the lock is held, `false` otherwise.

## Platform Support

| Platform | Supported |
|----------|-----------|
| Android  | ✅        |
| iOS      | ❌ (no-op) |
| Web      | ❌ (no-op) |
| Windows  | ❌ (no-op) |
| macOS    | ❌ (no-op) |
| Linux    | ❌ (no-op) |

On non-Android platforms, all methods complete successfully but perform no operations.

## Why Use Multicast Locks?

Android devices normally filter out multicast packets to save battery. When your app needs to receive multicast UDP packets (common in networking protocols, device discovery, etc.), you must acquire a multicast lock to ensure these packets are delivered to your app.

## Example

See the `example/` directory for a complete Flutter app demonstrating how to use this plugin.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

