# Contributing to liblsl.dart

Thank you for your interest in contributing to liblsl.dart!Contributions are very welcome and encouraged.  Please follow the [Code of Conduct](./CODE_OF_CONDUCT.md) when contributing to this project or interacting with the community in any way.

Please:

- Follow Dart's [effective dart](https://dart.dev/guides/language/effective-dart) style guide.
- Write tests for new features and bug fixes.
- Ensure all tests pass before submitting a pull request.

## Issues and Feature Requests

Please first check to see if there are any [issues or feature requests](https://github.com/NexusDynamic/liblsl.dart/issues) that you can work on. If not, please first open an issue for the feature you would like to work on, this helps to avoid duplicate work and provides an overview of what is being done.

## Monorepo and Packages

Because this is a monorepo with several subpackages, please follow any additional guidelines for the specific subpackages. In addition, remember to tag / label issues and PRs with the relevant package names.

This repository uses [melos](https://github.com/invertase/melos) to manage the monorepo and packages, so please make sure to familiarize yourself with it if you are not already.

## Basic setup

1. Fork the repository
2. Clone your forked repository to your local machine: `git clone --recurse-submodules https://github.com/<your-username>/liblsl.dart.git`
3. Create a feature branch (`git checkout -b feature/amazing-feature`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request, describing the change and make sure to link to any relevant issues or feature requests.

## Development environment

Please use FVM to work with this repository, which will help to keep things consistent and ensure that the tests are run against the appropriate version of the Dart SDK and Flutter (where appropriate). To install FVM, follow the [https://fvm.app/documentation/getting-started/overview](getting Started guide).

Make sure you have `llvm` / `clang` installed and available in your PATH, as this is required for compiling the C code and creating the shared library. You can check if clang is available by running `clang --version` in your terminal.
LLVM / Clang can be installed from here: https://github.com/llvm/llvm-project/releases/tag/llvmorg-18.1.8 or via your operating system package manager.


## Testing

Before submitting a PR, please ensure that all tests pass by running `fvm exec melos test`. The LSL-backed tests (`fvm exec melos test:lsl`) need a few thousand open files; liblsl raises the process limit itself when loaded, but if it warns that it could not, run `ulimit -S -n 65536` in the same shell first (see the [liblsl README](packages/liblsl/README.md#macos-and-linux-open-file-limit)). The serial and OpenBCI tests use `socat` for virtual serial ports, and are skipped without it. If your PR changes functionality or is a new feature, make sure that there are associated tests to ensure that it works, and will continue to work in the future.

## Formatting and linting

In addition to testing, please make sure to run `fvm exec melos format` and `fvm exec melos analyze` to ensure that your code is properly formatted and does not have any linting issues. This will help to keep the codebase clean and consistent.

## Releases (maintainers)

Every package and app is versioned on its own, and released by pushing a tag of the form `<package>-v<version>`, e.g. `liblsl-v1.0.0`, `xdf-v0.2.0` or `lsl_viewer-v0.1.0`. Unscoped tags (`v1.0.0`) are not released.

Releases are prepared with `tool/release.dart`, which knows how the packages of the workspace depend on each other.

1. Run `dart run tool/release.dart`. It lists every package with its version, its last tag, whether that version is on pub.dev and whether anything shipped has changed since the tag, followed by whatever stands in the way of a release: a constraint the workspace no longer satisfies, a missing `CHANGELOG.md` section, citation metadata at another version than `liblsl`, or a liblsl submodule commit that was never pushed.
2. Give each changed package its version with `dart run tool/release.dart bump <package> <version>` (or `patch`, `minor`, `major`). This sets the pubspec version, adds the `CHANGELOG.md` heading if there is none and, for `liblsl`, updates `CITATION.cff`, `codemeta.json` and `.zenodo.json`; for an app it updates the download links in the READMEs. With `--cascade`, every package that depends on the bumped one, directly or through others, has its constraint raised to the new version, receives a patch version of its own and a line in its `CHANGELOG.md`. Use it when dependents should require the new version, as after an important fix. `tool/release.sh <package> <version>` does the same.
3. Write the `CHANGELOG.md` sections, which become the release notes, commit, push to `main` and wait for the Test workflow to pass.
4. Run `dart run tool/release.dart tag` to see the tags that would be pushed, and again with `--push` to push them. Every package whose version is ahead of its last tag is tagged, dependencies first.

The tags are pushed one at a time because GitHub starts no workflow for a push that carries more than three tags. They need not be spaced out otherwise: before publishing, each release run waits until the workspace dependencies released with it are on pub.dev. The tool refuses to tag unless Test has passed on the commit, since each release run would otherwise repeat the whole suite.

The [release workflow](.github/workflows/release.yml) checks that the tag matches the pubspec (and the citation metadata for `liblsl`), runs the full test suite, and only then:

- publishes to pub.dev, for packages without `publish_to: none` (via [automated publishing](https://dart.dev/tools/pub/automated-publishing); each package needs it enabled on pub.dev with the tag pattern `<package>-v{{version}}`). A version already on pub.dev is not published again. pub.dev only offers automated publishing for packages that exist, so a new package's first version is published by hand (`dart pub publish`), and its tag then just creates the GitHub release;
- creates the GitHub release;
- for `liblsl`, attaches a source archive (with the liblsl C++ submodule) and uploads it and `.zenodo.json` to the Zenodo draft, which is then published by hand on Zenodo;
- for the apps in `apps/`, builds Linux, Windows, macOS and Android binaries, and a web build for the apps that have one, and attaches them to the release. A web build is also deployed to GitHub Pages (`/lsl_viewer/`, `/transport_timing_analysis/`). The same builds can be tried without releasing with the *Build app* workflow.

### Published packages

On pub.dev: everything in `packages/`. The apps in `apps/`, including `lsl_viewer`, have `publish_to: none`.

Packages depend on each other with normal version constraints (e.g. `peer_coordinator: ^0.4.0`); inside the workspace these resolve to the local packages. The release tool and workflow keep released packages in dependency order. A new package is the exception: it goes up by hand, in dependency order, before its tag is pushed:

1. `signal_core`, then `xdf`
2. `peer_coordinator`, then `webrtc_coordinator`, then `webrtc_coordinator_flutter`
3. `liblsl_coordinator`, once the `liblsl` version it needs is on pub.dev

Publish Flutter packages with `flutter pub publish`; the release workflow uses it for all packages.

## Support

Please see the [SUPPORT.md](./SUPPORT.md) file for information on how to get support for liblsl.dart and where to ask questions or discuss potential features.

Thank you 😊
