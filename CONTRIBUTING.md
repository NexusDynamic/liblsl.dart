# Contributing to liblsl.dart

Thank you for your interest in contributing to liblsl.dart!Contributions are very welcome and encouraged.  Please follow the [Code of Conduct](./CODE_OF_CONDUCT.md) when contributing to this project or interacting with the community in any way.

## Issues and Feature Requests

Please first check to see if there are any [issues or feature requests](https://github.com/NexusDynamic/liblsl.dart/issues) that you can work on. If not, please first open an issue for the feature you would like to work on, this helps to avoid duplicate work and provides an overview of what is being done.

## Monorepo and Packages

Because this is a monorepo with several subpackages, please follow any additional guidelines for the specific subpackages. In addition, remember to tag / label issues and PRs with the relevant package names.

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

## Support

You can ask for help or discuss potential features in the following places:

- [GitHub Discussions](https://github.com/orgs/NexusDynamic/discussions)
- [Matrix #liblsl.dart:neuro.wang](https://matrix.to/#/#liblsl.dart:neuro.wang)

Thank you 😊
