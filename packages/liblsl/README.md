# liblsl dart Lab Streaming Layer (LSL) library

This package provides a Dart wrapper for liblsl, using the dart native-assets build system and ffi.

It's currently considered experimental, but if it compiles, then you should be able to access the native liblsl functions from Dart.

That said, I'm also working on a convenience wrapper which you will be able to use to make the whole process easier and
not have to be concerned about the underlying types e.g. `Pointer<...>`. That will come in a later release.


## Testing

Currently (March 2025), the native assets are branch blocked so you will need to use flutter / dart "main" channel to work with this lib for development purposes.

```bash
dart --enable-experiment=native-assets test
```
