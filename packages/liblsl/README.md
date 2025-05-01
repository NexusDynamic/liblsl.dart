# liblsl dart Lab Streaming Layer (LSL) library

![Pub Publisher](https://img.shields.io/pub/publisher/liblsl?style=flat-square) ![Pub Version](https://img.shields.io/pub/v/liblsl)

This package provides a Dart wrapper for liblsl, using the dart native-assets build system and ffi.

It's currently considered experimental.

## Targets

- [x] Linux
- [x] OSX
- [x] Windows
- [x] iOS
- [x] Android
- [ ] Web - Possibly in the future, see: [`native_assets_cli` build.dart / link.dart web backends and WasmCode and JsCode assets](https://github.com/dart-lang/native/issues/988)

Also confirmed working on:

 - Meta Quest 2 (Android).
 - Raspberry Pi 4 (Linux/Raspberry Pi OS), only dart tested so far:
   
   `sudo apt update && sudo apt install build-essential clang llvm`
   
   `dart --enable-experiment=native-assets test`
   
   ![screenshot of tests passing on RPi](./doc/image.png)

## Introduction

The Lab Streaming Layer (LSL) is a system for streaming time series data, such as EEG or other physiological signals. It allows for real-time data sharing between different applications and devices.

LSL handles the heavy lifting of synchronizing data streams and managing the timing and drift correction of data. This can apply to time-critical real-time data, but can also be used to manipulate the data and pass it on to another stream or application.

You're not limited to EEG, LSL is used in all kinds of instrumentation, and you can also use it for non-frequent data streams, such as events or triggers, or even just passing messages and states between devices and applications. You can also use it to send message streams to a central logging server.

There's no need to go over all the details of LSL here, check out the excellent documentation for [LSL](https://labstreaminglayer.readthedocs.io/) and more information about [liblsl](https://labstreaminglayer.readthedocs.io/dev/app_dev.html#).

### Why this Dart package?

This package is a wrapper around the C++ liblsl library, allowing you to use LSL in your Dart applications. It uses the dart native-assets build system to compile the C++ code into a shared library that can be used in Dart.

What this means is that with very little effort, you can have bidirectional communcations in your Dart application on any supported platform, and can easily integrate it with any other LSL-enabled application or device.

### Flutter

This package will work with flutter without any issues, for an example see the [liblsl_test](../liblsl_test) package, which demonstrates an integration test that works on your device.

## Important notes

### Android

Your application will require the `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_NETWORK_STATE`, and `ACCESS_WIFI_STATE` permissions in your `AndroidManifest.xml` file. This is required for multicast UDP communication, which is used by LSL.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- ... other AndroidManifest.xml nodes -->
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
</manifest>
```

### iOS

There's a very unfortunate situation in iOS where you cannot access multicast networking without the special entitlement [`com.apple.developer.networking.multicast`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast). This is a special entitlement that is only available to Apple developers with a paid developer account, and by explicit request. If you don't have this entitlement, you will not be able to use LSL on iOS, and unfortunately, there's not much I can do about this. If you have a developer account, see the above entitlement documentation, and then visit the [Multicast Networking Entitlement Request page](https://developer.apple.com/contact/request/networking-multicast).

### General

Multicast packets may be blocked on various managed switches and routers, or by your network or machine firewall. If you are having issues with LSL, check your network settings and firewall settings to ensure that multicast packets are allowed, the method to do this varies by platform and network infrastructure.


## API Usage

More documentation will come, but see [liblsl_example.dart](./example/liblsl_example.dart), [liblsl_test.dart](./test/liblsl_test.dart) also see the [liblsl_test](../liblsl_test) package for a working example with flutter for all supported target devices.

```dart
import 'package:liblsl/liblsl.dart';

// Create a stream info
final info = await LSL.createStreamInfo(
  streamName: 'MyStream',
  streamType: 'EEG',
  channelCount: 8,
  nominalSrate: 100.0,
  channelFormat: ChannelFormat.float32,
  sourceId: 'EEGSystem',
);

// Create a stream outlet to send data
final outlet = await LSL.createOutlet(
    streamInfo: info,
    chunkSize: 0,
    maxBuffer: 1
);

// throws an exception if no consumer is found (e.g. lab recorder)
await outlet.waitForConsumer(timeout: 5.0);

// send a sample to the outlet
final sample = List<double>.filled(8, 0.0);

await outlet.pushSample(sample);

// To receive data, a stream inlet is needed,
// this should be from a resolved stream, although
// you could technically create it manually

// find max 1 of all availble streams
final streams = await LSL.resolveStreams(
    waitTime: 1.0,
    maxStreams: 1,
);

// create an inlet for the first stream
final inlet = await LSL.createInlet(streamInfo: streams[0]);

// get the sample
final sample = await inlet.pullSample();

// do something with the values
print('Sample: ${sample[0]}, timesatamp: ${sample.timestamp}');

// clear the streaminfos
streams.destroy();

// clear up memory from inlet, outlet, resolver, etc
inlet.destroy();
outlet.destroy();


```

## Direct FFI usage

If you want to use the FFI directly, you can do so by importing the `native_liblsl.dart` file.

```dart
import 'package:liblsl/native_liblsl.dart';
// Create a simple stream info
final streamNamePtr = "TestStream".toNativeUtf8().cast<Char>();
final streamTypePtr = "EEG".toNativeUtf8().cast<Char>();
final sourceIdPtr = "TestSource".toNativeUtf8().cast<Char>();

final streamInfo = lsl_create_streaminfo(
    streamNamePtr,
    streamTypePtr,
    1, // One channel
    100.0, // 100Hz sample rate
    lsl_channel_format_t.cft_string, // String format
    sourceIdPtr,
);

// Create outlet
final outlet = lsl_create_outlet(streamInfo, 0, 1);

// Create a string sample (as an array of strings)
final sampleStr = "Test Sample".toNativeUtf8().cast<Char>();
final stringArray = malloc<Pointer<Char>>(1);
stringArray[0] = sampleStr;

// Push the sample
final result = lsl_push_sample_str(outlet, stringArray);

// Assert the result
expect(result, 0); // 0 typically means success

// Clean up
lsl_destroy_outlet(outlet);
lsl_destroy_streaminfo(streamInfo);
streamNamePtr.free();
streamTypePtr.free();
sourceIdPtr.free();
sampleStr.free();
stringArray.free();
```

## Testing

Currently (March 2025), the native assets are branch blocked so you will need to use flutter / dart "main" channel to work with this lib for development purposes.

```bash
dart --enable-experiment=native-assets test
```
