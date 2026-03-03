# Outline for testing the Dart liblsl package

This is just a rough guide for testing options for this package. It will give some ideas based on which devices you have access to.

<!-- vscode-markdown-toc -->
* 1\. [Initial setup](#Initialsetup)
	* 1.1. [Getting the code](#Gettingthecode)
	* 1.2. [Installing Dart and Flutter](#InstallingDartandFlutter)
		* 1.2.1. [Option 1: FVM](#Option1:FVM)
		* 1.2.2. [Option 2: Manual installation](#Option2:Manualinstallation)
	* 1.3. [Preparing the environment](#Preparingtheenvironment)
* 2\. [Testing process](#Testingprocess)
	* 2.1. [First time setup](#Firsttimesetup)
	* 2.2. [Automated tests](#Automatedtests)
* 3\. [Integration testing](#Integrationtesting)
	* 3.1. [liblsl_test example application for testing](#liblsl_testexampleapplicationfortesting)
		* 3.1.1. [Running the precompiled binaries](#Runningtheprecompiledbinaries)
	* 3.2. [Testing with another LSL enabled device or application](#TestingwithanotherLSLenableddeviceorapplication)
		* 3.2.1. [Using a `Stream Viewer` application](#UsingaStreamViewerapplication)
* 4\. [Anything else?](#Anythingelse)

<!-- vscode-markdown-toc-config
	numbering=true
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

##  1. <a name='Initialsetup'></a>Initial setup

**Note: Flutter is not required for using the liblsl package, but if you want to run some of the example apps, then you will need to have Flutter installed.**

###  1.1. <a name='Gettingthecode'></a>Getting the code

- Clone the repository: `git clone --recurse-submodules https://github.com/NexusDynamic/liblsl.dart.git`

*Note the `--recurse-submodules` flag, this is required because the C liblsl code is included as a git submodule.*

###  1.2. <a name='InstallingDartandFlutter'></a>Installing Dart and Flutter

####  1.2.1. <a name='Option1:FVM'></a>Option 1: FVM

FVM is probably the easiest way to go here both if you do not have an existing Dart/Flutter setup and also if you have other projects, this will help avoid version conflicts.

- Install FVM, following the Getting Started guide: https://fvm.app/documentation/getting-started/overview
- This project has a `.fvmrc` file in the repository root that a correctly installed FVM will recognize.

The version of flutter is expected to be beta or dev/main[^1].

####  1.2.2. <a name='Option2:Manualinstallation'></a>Option 2: Manual installation

- Get the latest beta or dev (main) release of the Flutter SDK from https://docs.flutter.dev/install/archive
- Follow the normal installation instructions for your OS here: https://docs.flutter.dev/install/manual
  - Just make sure to use the archive you downloaded in the previous step instead of the stable release.
  - If you used the beta release, you can also switch to the dev channel by running `flutter channel main` and then `flutter upgrade`.


###  1.3. <a name='Preparingtheenvironment'></a>Preparing the environment

There is little beyond the normal Dart/Flutter setup required, but you should have clang installed and available in your PATH, as this is required for compiling the C code and creating the shared library. You can check if clang is available by running `clang --version` in your terminal.
LLVM / Clang can be installed from here: https://github.com/llvm/llvm-project/releases/tag/llvmorg-18.1.8 but there is probably a version available through your package manager (e.g. `apt`, `pacman`, `brew`, `choco`, `winget`, etc.) that you can install.


##  2. <a name='Testingprocess'></a>Testing process

###  2.1. <a name='Firsttimesetup'></a>First time setup

- Run `flutter pub get` in the repository root to get the dependencies.
- Switch to the `packages/liblsl` directory, as the other packages are not relevant for testing the liblsl package.

###  2.2. <a name='Automatedtests'></a>Automated tests

There is a suite of automated tests that are included that test for core functionality. These explicitly only bind to the local / loopback interface, this means that any test streams will not be visible on your LAN (nor will it cause any traffic increase).

The first time you run the tests, it will take a little longer because of the library compilation. Subsequent runs will be faster.

- run `dart test` from the `packages/liblsl` directory, this runs all the tests in the `test` directory.

**Note: The performance tests take some time, you can skip those by running `dart test --exclude=performance` if you want to run the other tests more quickly.**

Expect to see some error lines from liblsl that say `Stream transmission broke off (Input stream error.); re-connecting..`. This is expected behaviour because we close streams during testing, and liblsl is warning us that the stream was closed.

The automated tests consist of the following:

- `test/liblsl_performance_test.dart`: This is a *very rough*  performance test that just ensures that many concurrent streams can be handled. The timing on this type of testing is inaccurate and will vary per run as it relies on polling for data and sending data at a fixed frequency.

- `test/liblsl_resolver_test.dart`: These tests ensure that liblsl can find and recognize streams using various methods.

- `test/liblsl_stream_info_metadata_test.dart`: These tests ensure that the metadata parsing and handling is working correctly. Liblsl uses a XML payload with additional information about a stream. This may include arbitrary data from a user.

- `test/liblsl_test.dart`: This tests all the core API functionality, such as creating streams, sending data, receiving data. It also tests the FFI bindings directly to ensure that they are working correctly.

##  3. <a name='Integrationtesting'></a>Integration testing

Of course, the automated tests only cover some of the functionality, and are limited to the loopback network interface. In order to test it within an app, and to test the network / LAN functionality, there is a specific example app that can do this.

###  3.1. <a name='liblsl_testexampleapplicationfortesting'></a>liblsl_test example application for testing

For the purposes of review, testing, there are [precompiled binaries of the `liblsl_test` application available](https://github.com/NexusDynamic/liblsl.dart/releases/tag/liblsl_test_preview), these are for linux-x64, MacOS (universal), android (universal APK) and Windows-x64.

The source code for this application is available in the [`liblsl_test` package](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/liblsl_test).

This application has the following features you may find useful in testing:

- Produce LSL streams at various frequencies and channel counts
- Stream for a specified duration
- Find and list LSL streams on the network (including the loopback/local interface)
- Start consuming a network stream and print the latest captured sample

You may run this application on multiple devices on the same network and the streams should be visible between them (with the caveats mentioned in [README.md](./README.md) regarding network configuration and firewalls and handling of multicast / UDP packets).

####  3.1.1. <a name='Runningtheprecompiledbinaries'></a>Running the precompiled binaries

Just download, extract and run the binary for the platform, it should be straightfowrward. For Android, you will need to install the APK via the default package manager, or via `adb install`.

###  3.2. <a name='TestingwithanotherLSLenableddeviceorapplication'></a>Testing with another LSL enabled device or application

You may use the `liblsl_test` application along with another LSL enabled device or application, to check and verify the streams. The exact process of this depends on your specific process.

####  3.2.1. <a name='UsingaStreamViewerapplication'></a>Using a `Stream Viewer` application

You can, for example use a standard LSL stream viewer application, such as [the ones listed on the labstreaminglayer documentation site](https://labstreaminglayer.readthedocs.io/info/viewers.html). While you are producing streams of data in `liblsl_test`, you will be able to see the stream output in one of the stream viewer applications.

Similarly, if you have another source for LSL streams, you can see those streams in the `liblsl_test` application and verify that the data is being received correctly.

##  4. <a name='Anythingelse'></a>Anything else?

If something is wrong with this guide or something doesn't work as expected, please let me know, and I can update either the guide, or the app.


[^1]: The reason that this package does not yet use dart stable is because the [`native_toolchain_c`](https://pub.dev/packages/native_toolchain_c) package is still in experimental status, but this is required for compiling the liblsl C code and creating the shared lib and FFI bindings. When `native_toolchain_c` reaches stable, then this package will be updated to use the stable Dart SDK. Additionally, this package can be used with the stable Dart SDK, but for development and testing purposes, the dev/beta release is required.
