import 'dart:ffi' as ffi;

import 'package:liblsl/native_liblsl.dart';

/// Hand-written bindings for the `*_ex` creation functions.
///
/// The generated wrappers in `native_liblsl.dart` accept a single
/// [lsl_transport_options_t] enum value, which cannot express bitwise-OR'd
/// flag combinations (e.g. `transp_bufsize_samples | transp_sync_blocking`),
/// and the raw `int flags` externals there are library-private. These
/// bindings take the combined flags as a plain int.
///
/// The `assetId` must name the generated bindings library, because that is
/// the asset id registered by the native-assets build hook
/// (`hook/build.dart` sets `assetName: 'native_liblsl.dart'`).

@ffi.Native<NativeLsl_create_outlet_ex>(
  symbol: 'lsl_create_outlet_ex',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external lsl_outlet lslCreateOutletFlags(
  lsl_streaminfo info,
  int chunkSize,
  int maxBuffered,
  int flags,
);

@ffi.Native<NativeLsl_create_inlet_ex>(
  symbol: 'lsl_create_inlet_ex',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external lsl_inlet lslCreateInletFlags(
  lsl_streaminfo info,
  int maxBuflen,
  int maxChunklen,
  int recover,
  int flags,
);

// Leaf-call overrides for hot, guaranteed-short native functions.
//
// `isLeaf: true` skips the VM's generic FFI transition (no safepoint, no
// stack walking), shaving substantial per-call overhead — but a leaf call
// must never block, re-enter Dart, or run long. That limits it to:
//  - lsl_local_clock: reads a monotonic clock.
//  - lsl_have_consumers / lsl_samples_available: read an atomic/counter.
//  - lsl_inlet_flush: drops buffered samples without I/O.
// Explicitly NOT leaf: all pull calls (block up to their timeout), all push
// calls (block on socket writes under transp_sync_blocking), create/destroy,
// lsl_open_stream and lsl_wait_for_consumers (network I/O and locks).

@ffi.Native<NativeLsl_local_clock>(
  symbol: 'lsl_local_clock',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external double lslLocalClockFast();

@ffi.Native<NativeLsl_have_consumers>(
  symbol: 'lsl_have_consumers',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external int lslHaveConsumersFast(lsl_outlet out);

@ffi.Native<NativeLsl_samples_available>(
  symbol: 'lsl_samples_available',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external int lslSamplesAvailableFast(lsl_inlet in$);

@ffi.Native<NativeLsl_inlet_flush>(
  symbol: 'lsl_inlet_flush',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external int lslInletFlushFast(lsl_inlet in$);
