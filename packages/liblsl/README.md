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

Also confirmed working on Meta Quest 2 (Android).


## API Usage

More documentation will come, but see [liblsl_test.dart](./test/liblsl_test.dart) also see the [liblsl_test](../packages/liblsl_test) package for a working example with flutter for all supported target devices.

```dart
import 'package:liblsl/liblsl.dart';

// Create the helper
final lsl = LSL();

// Create a stream info
final info = StreamInfo(
  streamName: 'MyStream',
  streamType: 'EEG',
  channelCount: 8,
  nominalSrate: 100.0,
  channelFormat: ChannelFormat.float32,
  sourceId: 'EEGSystem',
);

// Create a stream outlet to send data
final outlet = await lsl.createOutlet(
    chunkSize: 0,
    maxBuffer: 1
);

// throws an exception if no consumer is found (e.g. lab recorder)
await outlet.waitForConsumer(timeout: 5.0);

// send a sample to the outlet
final sample = List<double>.filled(8, 0.0);

await lsl.outlet?.pushSample(sample);

// To receive data, a stream inlet is needed,
// this should be from a resolved stream, although
// you could technically create it manually

// find max 1 of all availble streams
final streams = await lsl.resolveStreams(
    waitTime: 1.0,
    maxStreams: 1,
);

// create an inlet for the first stream
final inlet = await lsl.createInlet(streamInfo: streams[0]);

// get the sample
final sample = await inlet.pullSample();

// do something with the values
print('Sample: ${sample[0]}, timesatamp: ${sample.timestamp}');

// clear the streaminfos
streams.destroy();

// clear up memory from inlet, outlet, resolver, etc
lsl.destroy();

```

## Direct FFI usage

If you want to use the FFI directly, you can do so by importing the `liblsl.dart` file.

```dart
import 'package:liblsl/liblsl.dart';
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
