# Liblsl.dart

[![melos](https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square)](https://github.com/invertase/melos) [![CI Test](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml/badge.svg)](https://github.com/NexusDynamic/liblsl.dart/actions/workflows/test.yml)

This is the monorepo for the dart native liblsl package.

Subpackages:

- [liblsl](./packages/liblsl): The main package for liblsl. [![Pub Publisher](https://img.shields.io/pub/publisher/liblsl?style=flat-square)](https://pub.dev/publishers/zeyus.com/packages) [![Pub Version](https://img.shields.io/pub/v/liblsl)](https://pub.dev/packages/liblsl) [![status](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40/status.svg)](https://joss.theoj.org/papers/2d813b551058e59edacefd35ea281e40)
  - [JOSS paper](./packages/liblsl/paper/paper.md): markdown version of the JOSS paper 
- [liblsl_test](./packages/liblsl_test): An integration test so you can try out liblsl with flutter on any supported target platform.
- [liblsl_timing](./packages/liblsl_timing): App based multi-device latency, sync and interactive timing tests with automatic device coordination via LSL
- [liblsl_analysis](./packages/liblsl_analysis): Analysis of results from the timing tests in [liblsl_timing](./packages/liblsl_timing)

## Contributing

See the [CONTRIBUTING.md](./CONTRIBUTING.md) file for guidelines on how to contribute to this project.

## Code of Conduct

This project and everyone participating in it must uphold [Code of Conduct](./CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Support

Please see the [SUPPORT.md](./SUPPORT.md) file for information on how to get support for liblsl.dart and where to ask questions or discuss potential features.

## Security

Please see the [SECURITY.md](./SECURITY.md) file for information on how to report security vulnerabilities for liblsl.dart.

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.
