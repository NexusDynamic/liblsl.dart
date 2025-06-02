# 0.7.0

This release is a major update that includes breaking changes. This update provides a large performance improvement by reusing a buffer for samples, reducing the number of allocations and copies required when sending samples.

There are also new packages that complement `liblsl.dart`, and are still work-in-progress, but will allow setting up an entire experiment workflow without requiring any programming. Currently these packages include:

- [liblsl_timing](https://github.com/zeyus/liblsl.dart/tree/main/packages/liblsl_timing): This package provides an application for measuring LSL timing performance with your specific device and network configuration. The test app automatically coordinates between all connected devices on the network, and passes the test configuration via a coordinator - the coordinator is the first device that starts the application. There are three tests included:
  - **Latency**: This test measures the latency of sending and receiving samples over LSL at the specified frequency.
  - **Sync**: This test is intended to measure the clock synchronization and drift between devices.
  - **Interactive**: This test has a button on screen and when the button is pressed, an LSL sample is sent, all receiving devices will then flash a black square on the screen. This test is intended to measure the entire end-to-end latency, including Flutter rendering, input and display lag. To measure this effectively, it would be ideal to have a touch sensor of some kind (e.g. FSR) and a photodiode sensor to measure the moment of touch and the moment of display change, respectively. There is a companion app in C++ written for a Bela (Beaglebone Black) which takes digital inputs and logs the timestamps along with the LSL samples. You can see more at the [bela-lsl-timing](https://github.com/zeyus/bela-lsl-timing) repository.
- [liblsl_analysis](https://github.com/zeyus/liblsl.dart/tree/main/packages/liblsl_analysis): This package allows for analysis of the data provided by the `liblsl_timing` package. It currently only allows loading a single TSV file from the timing test, but will be updated to allow loading files from all the reporting devices to create a comprehensive report of the timing performance across all devices. The report will include:
  - Latency statistics for each device
  - Clock synchronization and drift statistics
  - Interactive test results with timestamps and latency measurements (if available)
- Use [custom fork](https://github.com/zeyus/liblsl) of `liblsl` which allows API configuration to be specified at runtime (once, before any other LSL functions are called). This means that anything in the [LSL API configuration file](https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#configuration-file-contents) can be set, including on mobile platforms that do not support environment variables or allow editing files in `/etc` or `./`.
  - This is exposed via the C/C++ API as `lsl_set_config_filename` and `lsl_set_config_content` to set the configuration file name and content (directly as a `std::string`/`char*`), respectively. The Dart API now provides a `LSLConfig` class that can be used to set the configuration file name and content, which can be used in `LSL.setConfigFilename` and `LSL.setConfigContent` methods.
- New `LSLReusableBuffer` class for allowing sample structures to avoid creating new instances for each sample. This reuse significantly enhances the performance by reducing the allocations during sample pulling and pushing.
- Generic push sample functions have now been replaced with specific implementations for each type e.g. `LslPushSampleFloat`.
- A new helper function `runPreciseInterval` has been added to handle precision interval timing, using an adjustable busy-wait loop. The API is subject to change, but allows for a callback and a mutable `dyanmic state` to be passed in, which can be used to update the state of the callback. This is useful for implementing precise timing in LSL applications (such as requiring 1000Hz sample creation with high precision -> resulting in a mean of 1.0000, median of 1.0082 ms over 180,000 samples).
- `hooks` package updated from `0.19.0` to `0.19.1`.
- `native_toolchain_c` updated from `^0.16.0` to `^0.16.1`.
- `ffigen` updated from `18.1.0` to `19.0.0`.
- `test` package updated from `1.25.15` to `1.26.0`.

# 0.6.2-dev.0

- Make SDK constraint ^3.9.0-0

# 0.6.1

- Attempt to fix package issue on pub.dev
- bump dart SDK constraint to ^3.9.0 due to `hooks` package
- Added `LSLStreamResolver` mixin (empty for now).
- Added `dartdoc` dev dependency, and added `doc` directory to `.gitignore`

# 0.6.0

- New `LSLIsolatedInlet.getTimeCorrection` method to get the LSL reported sample time correction
- Removed deprecated `LSLStreamInlet` and `LSLStreamOutlet` classes
- Remove deprecated `native_assets_cli` dependency
- Add `hooks` `0.19.0` dependency instead of `native_assets_cli`
- Add `code_assets` `0.19.0`
- Update `native_toolchain_c` to `^0.16.0`

# 0.5.1

- Fix package name on Android
- Update `ffigen` to `18.1.0`
- Update `native_assets_cli` to `0.14.0`
- Update `native_toolchain_c` to `0.11.0`

# 0.5.0

- Generated dylib is now without the lib prefix (if it is the prefix on the platform). i.e. `libliblsl.so` is now just `liblsl.so`
- Tested working on Raspberry Pi 4 (64bit)
- Tests are now less chatty

# 0.4.1

- Update `native_assets_cli` to `0.13.0`
- Update `native_toolchain_c` to `0.10.0`

# 0.4.0

- Inlet and outlets now pass sample pointer addresses rather than sample objects, making them more efficient (note: this has no public facing changes to the API)
- Updated the `liblsl_test` package (android NDK version, entitlements, manifests)
- Updated readme documentation, describing Android and iOS specifics

# 0.3.0

- Outlets and inlets now have to be destroyed by the user
- Outlets and inlets are now contained in `Isolate`s
- Updated liblsl to `7e61a2e`
- Added a fully self-contained example

# 0.2.1

- Fixed linting issues.

# 0.2.0

- Restructured API, renamed `liblsl` to `native_liblsl`.

# 0.1.2

- Updated `native_assets_cli` to `0.12.0`
- Updated `native_toolchain_c` to `0.9.0`
- Removed spurious `api.dart` file (might come back later)

# 0.1.1

- Added missing `meta` dependency

# 0.1.0

- Restructured everything to be a bit more modular
- There's now an API for all the basic LSL functions 🥳🎈
- Started adding docs
- Test includes pushing and pulling a sample


# 0.0.2

- Android support 🎉

# 0.0.1

- Initial release
- Native compilation confirmed working on Windows, OSX and iOS. Will be testing Linux and Android soon.
