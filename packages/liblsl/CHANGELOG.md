# 0.10.0+0

- Expose `LSLInlet<T>.inlet` which returns the underlying `lsl_inlet` pointer.
- Expose `LSLOutlet<T>.inlet` which returns the underlying `lsl_outlet` pointer.
- Added methods for creating an inlet and outlet from the pointer directly: `LSLInlet.createFromPointer` and `LSLOutlet.createFromPointer`.
- Performance test use the above to allow a single isolate for all outlets, and a single isolate for all inlets, reducing overhead and improving performance.
- All non-performance tests made concurrency safe, which reduces test-suite run time. Performance tests still need to be run without concurrency to ensure accurate(ish) timing.
- Exported some lower-level classes for advanced use cases: `LslPullSample`, `LslPushSample`, `LSLMapper`, `LSLSamplePointer`, `LSLReusableBuffer`, `LSLReusableBufferInt8`, `LSLReusableBufferDouble` and `LSLReusableBufferFloat`.
- Added advanced methods `LSLInlet.pullSamplePointerSync()` which returns a `LSLSamplePointer` and `LSLOutlet.dataToBufferPointer` which returns a buuffer pointer for pushing samples.
- Replace `List` with `IList` for sample management from `fast_immutable_collections` for better performance and immutability guarantees.
- Added a check for `created` state in `LSLInlet.destroy` and `LSLOutlet.destroy` to avoid trying to destroy uncreated inlets/outlets.
- Isolated inlet and outlet now pass sample pointers as opposed to sample objects with dart collections, preventing copying between isolates and improving performance.
- Improved performance of precise interval scheduling functions by reusing a single stopwatch instance and removing bounds checks, also will refuse to sleep if interval is below 1000 microseconds to avoid oversleeping.

# 0.9.1

- Updated `hooks` from `^0.20.0` to `^0.20.1`.
- Updated `code_assets` from `^0.19.0` to `^0.19.7`.
- Updated LSL Api config documentation
- Updated readme
- Improved tests and added a performance test
- Added an async version of `runPreciseInterval` (`runPreciseIntervalAsync`) that works with async callbacks
- Added continous stream resolvers by property and predicate (`LSLStreamResolverContinuousByProperty` and `LSLStreamResolverContinuousByPredicate`)
- `LSL.createInlet` now returns the typed version of the inlet rather than dynamice (e.g. `LSLInlet<double>` rather than `LSLInlet<dynamic>`)
- Added draft JOSS paper

# 0.9.0

This is a major update that includes breaking changes. It introduces a new `LSLStreamInfoWithMetadata` class that allows for operations aligned with the C/C++ API that support reading and manipulation of the metadata associated with a stream. By default, when resolving streams, the metadata is not included and can only be retrieved after creating an inlet with the new method `LSLInlet.getFullInfo`, or, during inlet creation, you may pass `includeMetadata: true` to the constructor to include the metadata in the inlet.

In addition, the stream resolver methods have been updated, and now there are `LSL.resolveStreamsByProperty` and `LSL.resolveStreamsByPredicate` methods to filter streams during the resolution process. The `LSL.resolveStreams` method will still continue to resolve all available streams. The continuous versions of the filtered resolvers have not yet been implemented, but will be in the next release.

## Main changes in this release:
- 🚀 Introduced `LSLStreamInfoWithMetadata` class that allows for reading and manipulating stream metadata, aligning with the C/C++ API.
- 🚀 Updated stream resolvers, and added `LSL.resolveStreamsByProperty` and `LSL.resolveStreamsByPredicate` methods to the main `LSL` class.
- 🚀 Updated `LSLInlet` to include a new method `getFullInfo` that retrieves the full stream info with metadata.
- 🚀 Updated `LSLInlet` constructor with the `includeMetadata` property.
- 🚀 Added `resetUid` method to `LSLStreamInfo``
  - This method was also added to `liblsl`
- Forked `liblsl` version updated to commit `bea40e2c`.
- Added a bunch of `XML` classes to handle the metadata, which group children and can be used for creating nodes or traversing the XML tree.

# 0.8.1

Dependency updates. Added a new static method `createContinuousStreamResolver` to the `LSL` class for creating and managing your own continuous stream resolver, existing stream resolver method works the same, but now you have the option to keep resolving streams in the background while the API is being used.

- Updated `hooks` from `^0.19.1` to `^0.20.0`.
- Updated `native_toolchain_c` from `^0.16.1` to `^0.17.1`.

# 0.8.0

🚨🚨🚨 This is a major update that includes breaking changes 🚨🚨🚨

It brings the awesome new ability to choose if you want to use isolates or not, and if not, you get access to synchronous methods for pulling and pushing samples. This update also includes some minor API changes to improve consistency and usability. 

- 🚀 `LSLIsolatedInlet` and `LSLIsolatedOutlet` have been replaced with `LSLInlet` and `LSLOutlet`, respectively. The new classes both run by default in isolated mode, but can be configured to run without isolates by passing `useIsolates: false` to the constructor. This allows for more flexibility in how the LSL API is used, while still providing the benefits of isolates for performance and concurrency.
    - This also means that there are now `*Sync` methods for some common operations, such as `pullSampleSync`, `pushSampleSync`, etc. These methods allow for synchronous operations without isolates, which can be useful in some cases for more precise control over timing and performance.
- 🚀 `LSLInlet` and `LSLOutlet` buffer length and chunk size parameters have been consistently renamed to `maxBuffer` and `chunkSize`, respectively, to better reflect their purpose and usage, and to have a consistent naming scheme across the API.
- 🚀 The `streamInfo` parameter in `LSLInlet` and `LSLOutlet` constructors has been made a positional parameter, to make it less verbose to create inlets and outlets.
- 🚀 The `LSLStreamInfo.streamInfo` property is no longer nullable, and will instead throw an exception if the stream info is not set. This avoids having to do null checks when using the stream info pointer.
- 🚀 The `LSL.createInlet` and `LSL.createOutlet` convenience methods now have the additonal `useIsolates` parameter, which allows for creating inlets and outlets without isolates if set to `false`. This is useful for cases where isolates are not needed or desired, such as when using the API in a synchronous context.

# 0.7.1

This is a minor change that requires the dev/main version of the Dart SDK, as `hooks` and `native_toolchain_c` still require a version later than the last stable release. This is a temporary change until the next supported stable Dart SDK release.

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


## Main changes in this release:

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
