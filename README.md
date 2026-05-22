# Liblsl.dart

[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos) [![CI Test](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml/badge.svg)](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml)

This is the monorepo for the dart native liblsl package.

Subpackages:

- [liblsl](./packages/liblsl): The main package for liblsl. [![Pub Publisher](https://img.shields.io/pub/publisher/liblsl?style=flat-square)](https://pub.dev/publishers/zeyus.com/packages) [![Pub Version](https://img.shields.io/pub/v/liblsl)](https://pub.dev/packages/liblsl) [![status](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40/status.svg)](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40) [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20340247.svg)](https://doi.org/10.5281/zenodo.20340247) 

  - [JOSS paper](./packages/liblsl/paper/paper.md): markdown version of the JOSS paper 
- [liblsl_test](./packages/liblsl_test): An integration test so you can try out liblsl with flutter on any supported target platform.
- [liblsl_timing](./packages/liblsl_timing): App based multi-device latency, sync and interactive timing tests with automatic device coordination via LSL
- [liblsl_analysis](./packages/liblsl_analysis): Analysis of results from the timing tests in [liblsl_timing](./packages/liblsl_timing)

## Getting Started

You're most likely interested in the [liblsl](./packages/liblsl) package, which is the main package for liblsl.dart. You can find installation instructions and usage examples in the [README](./packages/liblsl/README.md) of that package. API documentation, and the Dart package are available on pub.dev: [https://pub.dev/packages/liblsl](https://pub.dev/packages/liblsl).

### Working with the monorepo

This is a monorepo managed with [melos](https://melos.invertase.dev/~melos-latest) and [fvm](https://fvm.app/). To get started, clone this repository *including submodules*:

```bash
git clone --recurse-submodules
```

[Install fvm](https://fvm.app/documentation/getting-started/installation), then run:

```bash
cd liblsl.dart
fvm dart pub get
```

There are some helpful melos commands for working with the monorepo:

- `fvm exec melos run <script>`: run a script defined in the `melos` `scripts` section of the root `pubspec.yaml` across all packages. For example, `melos run format` runs `dart format .` in all packages.
- `fvm exec melos run lint:all`: run `dart analyze` and `dart format` for all packages, and fail if there are any warnings or formatting issues.
- `fvm exec melos run test`: run `dart test` for all packages.

The lint and test scripts at the very least should be run before pushing any changes. For more scripts available, see the [pubspec.yaml](./pubspec.yaml) file.

## Contributing

See the [CONTRIBUTING.md](./CONTRIBUTING.md) file for guidelines on how to contribute to this project.

## Code of Conduct

This project and everyone participating in it must uphold [Code of Conduct](./CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Support

Please see the [SUPPORT.md](./SUPPORT.md) file for information on how to get support for liblsl.dart and where to ask questions or discuss potential features.

[![Matrix chat room](https://img.shields.io/matrix/NexusDynamic%3Aneuro.wang?server_fqdn=matrix.neuro.wang&fetchMode=summary&logo=matrix&label=Matrix%20Chat%20Room)
](https://matrix.to/#/#NexusDynamic:neuro.wang)

## Security

Please see the [SECURITY.md](./SECURITY.md) file for information on how to report security vulnerabilities for liblsl.dart.

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
