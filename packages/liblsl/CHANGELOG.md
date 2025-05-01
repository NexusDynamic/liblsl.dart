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
