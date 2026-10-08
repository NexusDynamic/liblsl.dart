# liblsl_test

`liblsl_test` is a Flutter application for checking that
[`liblsl`](../../packages/liblsl) works on a given device. It shows the
version of the LSL library that was loaded, sends a test stream with a
selectable sampling rate and duration, and receives streams from the
network. Running it on two devices on the same network confirms that they
can exchange LSL streams.

The application runs on Windows, macOS, Linux, Android and iOS. Version
[1.1.1](https://github.com/NexusDynamic/liblsl.dart/releases/tag/liblsl_test-v1.1.1)
is available for Windows, macOS, Linux and Android
([all releases](https://github.com/NexusDynamic/liblsl.dart/releases?q=liblsl_test&expanded=true)).
The macOS build is unsigned and is opened the first time through the context
menu (right-click, *Open*).

## Building and testing

```bash
flutter run --release
```

An integration test starts the application, sends a stream and receives it
on the same device, which verifies the native bindings on that platform:

```bash
flutter test integration_test
```

The platform requirements are those of `liblsl`, described in its
[README](../../packages/liblsl/README.md#network-and-platform-notes). The
permission handling on Android may need updating for recent Android
versions.
