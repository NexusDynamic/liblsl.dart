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

Before submitting a PR, please ensure that all tests pass by running `fvm exec melos test`. If your PR changes functionality or is a new feature, make sure that there are associated tests to ensure that it works, and will continue to work in the future.

## Formatting and linting

In addition to testing, please make sure to run `fvm exec melos format` and `fvm exec melos analyze` to ensure that your code is properly formatted and does not have any linting issues. This will help to keep the codebase clean and consistent.

## Releases (maintainers)

Every package and app is versioned on its own, and released by pushing a tag of the form `<package>-v<version>`, e.g. `liblsl-v1.0.0`, `xdf-v0.2.0` or `lsl_viewer-v0.1.0`. Unscoped tags (`v1.0.0`) are not released.

1. Add a `# <version>` section to the package's `CHANGELOG.md`; it becomes the release notes.
2. Run `tool/release.sh <package> <version>`. It sets the pubspec version (and, for `liblsl`, the version in `CITATION.cff`, `codemeta.json` and `.zenodo.json`), then prints the commands to commit and tag.
3. Push the commit to `main`, then push the tag.

The [release workflow](.github/workflows/release.yml) checks that the tag matches the pubspec (and the citation metadata for `liblsl`), runs the full test suite, and only then:

- publishes to pub.dev, for packages without `publish_to: none` (via [automated publishing](https://dart.dev/tools/pub/automated-publishing); each package needs it enabled on pub.dev with the tag pattern `<package>-v{{version}}`);
- creates the GitHub release;
- for `liblsl`, attaches a source archive (with the liblsl C++ submodule) and uploads it and `.zenodo.json` to the Zenodo draft, which is then published by hand on Zenodo;
- for `lsl_viewer`, builds Linux, Windows, macOS, Android and web binaries, attaches them to the release and deploys the web build to GitHub Pages (`/lsl_viewer/`). The same builds can be tried without releasing with the *Build lsl_viewer* workflow.

## Support

Please see the [SUPPORT.md](./SUPPORT.md) file for information on how to get support for liblsl.dart and where to ask questions or discuss potential features.

Thank you 😊
