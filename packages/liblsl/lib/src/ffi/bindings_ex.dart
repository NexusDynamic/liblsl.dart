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

// The listener thread behind `LSLInlet.sampleStream()` and `chunkStream()`:
// `src/dart/sample_listener.cpp`. Not part of liblsl, so not in the generated
// bindings.

/// What the listener thread hands to its callback. One allocation, freed
/// with [lslDartBlockFree]; the pointers in it point into the same block.
final class LslDartBlock extends ffi.Struct {
  /// [lslDartBlockData], [lslDartBlockEnded] or [lslDartBlockFailed].
  @ffi.Int32()
  external int kind;

  /// [lslDartBlockEnded]: the liblsl error code that ended the listener, or 0.
  @ffi.Int32()
  external int error;

  @ffi.Int32()
  external int samples;

  /// How many samples, from the first, were in the inlet when [clock] was
  /// read.
  @ffi.Int32()
  external int ready;

  /// `lsl_local_clock()` as the pull that returned the first sample came
  /// back.
  @ffi.Double()
  external double clock;

  external ffi.Pointer<ffi.Double> timestamps;

  /// `samples * channels` values of the stream's format. For a string
  /// stream, that many strings one after another, each ending in a zero
  /// byte.
  external ffi.Pointer<ffi.Void> data;

  @ffi.Uint64()
  external int dataBytes;

  /// [lslDartBlockEnded] with an error: liblsl's message for it, or null.
  /// [lslDartBlockFailed]: why.
  external ffi.Pointer<ffi.Char> message;
}

/// [LslDartBlock.kind]: samples.
const int lslDartBlockData = 0;

/// [LslDartBlock.kind]: the thread's last block, after a stop or a failed
/// pull. It calls nothing after it.
const int lslDartBlockEnded = 1;

/// [LslDartBlock.kind]: the thread's last block, when it is leaving for a
/// reason of its own, which is in [LslDartBlock.message].
const int lslDartBlockFailed = 2;

final class LslDartListener extends ffi.Opaque {}

/// An inlet as the listener reaches it: counted, so that the last of the
/// `LSLInlet` and its listeners to let go destroys it.
final class LslDartInlet extends ffi.Opaque {}

/// Holds [inlet] for an `LSLInlet`; if [owned], the last release closes and
/// destroys it.
@ffi.Native<ffi.Pointer<LslDartInlet> Function(lsl_inlet, ffi.Int32)>(
  symbol: 'lsl_dart_inlet_new',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external ffi.Pointer<LslDartInlet> lslDartInletNew(lsl_inlet inlet, int owned);

// Not a leaf call: it may destroy the inlet.
@ffi.Native<ffi.Void Function(ffi.Pointer<LslDartInlet>)>(
  symbol: 'lsl_dart_inlet_release',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external void lslDartInletRelease(ffi.Pointer<LslDartInlet> inlet);

/// [lslDartInletRelease] for a [ffi.NativeFinalizer], which destroys the
/// inlet on a thread of its own.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'lsl_dart_inlet_finalize',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external void lslDartInletFinalize(ffi.Pointer<ffi.Void> inlet);

/// Releases an `LSLInlet`'s [LslDartInlet] if the inlet's isolate exits, or
/// the inlet is garbage collected, without having been destroyed.
final lslDartInletFinalizer = ffi.NativeFinalizer(
  ffi.Native.addressOf<
    ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>
  >(lslDartInletFinalize),
);

typedef LslDartBlockCallback =
    ffi.Void Function(ffi.Pointer<LslDartBlock> block);

@ffi.Native<
  ffi.Pointer<LslDartListener> Function(
    ffi.Pointer<LslDartInlet>,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Double,
    ffi.Double,
    ffi.Uint32,
    ffi.Int32,
    ffi.Pointer<ffi.NativeFunction<LslDartBlockCallback>>,
  )
>(
  symbol: 'lsl_dart_listener_start',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external ffi.Pointer<LslDartListener> lslDartListenerStart(
  ffi.Pointer<LslDartInlet> inlet,
  int format,
  int channels,
  int maxSamples,
  double coalesce,
  double wakeInterval,
  int maxBacklog,
  int failAfter,
  ffi.Pointer<ffi.NativeFunction<LslDartBlockCallback>> callback,
);

@ffi.Native<ffi.Pointer<ffi.Uint32> Function(ffi.Pointer<LslDartListener>)>(
  symbol: 'lsl_dart_listener_control',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external ffi.Pointer<ffi.Uint32> lslDartListenerControl(
  ffi.Pointer<LslDartListener> listener,
);

// Not a leaf call: it waits for the thread.
@ffi.Native<ffi.Void Function(ffi.Pointer<LslDartListener>)>(
  symbol: 'lsl_dart_listener_destroy',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external void lslDartListenerDestroy(ffi.Pointer<LslDartListener> listener);

@ffi.Native<ffi.Void Function(ffi.Pointer<LslDartBlock>)>(
  symbol: 'lsl_dart_block_free',
  assetId: 'package:liblsl/native_liblsl.dart',
  isLeaf: true,
)
external void lslDartBlockFree(ffi.Pointer<LslDartBlock> block);

/// Stops a listener whose isolate is going away without having destroyed
/// it. A [ffi.NativeFinalizer] callback; see `sample_listener.dart`.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'lsl_dart_listener_abandon',
  assetId: 'package:liblsl/native_liblsl.dart',
)
external void lslDartListenerAbandon(ffi.Pointer<ffi.Void> listener);
