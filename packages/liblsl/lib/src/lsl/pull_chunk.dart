import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer;
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// Generalized `lsl_pull_chunk_*` signature: fills a flat data buffer and a
/// per-sample timestamp buffer, returns the number of data *elements* read.
typedef DartLSLPullChunk<T extends NativeType> =
    int Function(
      lsl_inlet inlet,
      Pointer<T> dataBuffer,
      Pointer<Double> timestampBuffer,
      int dataBufferElements,
      int timestampBufferElements,
      double timeout,
      Pointer<Int32> ec,
    );

/// The base class for chunk pull operations, one subclass per channel format.
///
/// Data lands as a flat buffer of `sampleCount * channelCount` values in
/// sample-major order with one timestamp per sample.
abstract class LSLPullChunk<T extends NativeType, D> {
  final DartLSLPullChunk<T> _pullFn;

  const LSLPullChunk(this._pullFn);

  /// Pulls up to [maxSamples] frames into [data]/[timestamps].
  ///
  /// Returns the number of data elements read (`samples * channels`).
  /// [timeout] only applies when no sample is buffered yet.
  int pullInto(
    lsl_inlet inlet,
    Pointer<NativeType> data,
    Pointer<Double> timestamps,
    int maxSamples,
    int channels,
    double timeout,
    Pointer<Int32> ec,
  ) {
    return _pullFn(
      inlet,
      data.cast(),
      timestamps,
      maxSamples * channels,
      maxSamples,
      timeout,
      ec,
    );
  }

  /// Allocates a flat native buffer of [elements] values.
  Pointer<T> allocBuffer(int elements);

  /// Converts [samples] frames from the flat [buffer] to lists of Dart values.
  List<List<D>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  );

  /// Copies [elements] values from [buffer] into a fresh [TypedData] (safe
  /// to keep after subsequent pulls). Unsupported for string streams.
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements);
}

class LSLPullChunkFloat extends LSLPullChunk<Float, double> {
  const LSLPullChunkFloat() : super(lsl_pull_chunk_f);

  @override
  Pointer<Float> allocBuffer(int elements) => allocate<Float>(elements);

  @override
  List<List<double>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Float>();
    return List<List<double>>.generate(samples, (s) {
      final base = s * channels;
      return List<double>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Float32List.fromList(buffer.cast<Float>().asTypedList(elements));
  }
}

class LSLPullChunkDouble extends LSLPullChunk<Double, double> {
  const LSLPullChunkDouble() : super(lsl_pull_chunk_d);

  @override
  Pointer<Double> allocBuffer(int elements) => allocate<Double>(elements);

  @override
  List<List<double>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Double>();
    return List<List<double>>.generate(samples, (s) {
      final base = s * channels;
      return List<double>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Float64List.fromList(buffer.cast<Double>().asTypedList(elements));
  }
}

class LSLPullChunkInt8 extends LSLPullChunk<Char, int> {
  const LSLPullChunkInt8() : super(lsl_pull_chunk_c);

  @override
  Pointer<Char> allocBuffer(int elements) => allocate<Char>(elements);

  @override
  List<List<int>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Int8>();
    return List<List<int>>.generate(samples, (s) {
      final base = s * channels;
      return List<int>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Int8List.fromList(buffer.cast<Int8>().asTypedList(elements));
  }
}

class LSLPullChunkInt16 extends LSLPullChunk<Int16, int> {
  const LSLPullChunkInt16() : super(lsl_pull_chunk_s);

  @override
  Pointer<Int16> allocBuffer(int elements) => allocate<Int16>(elements);

  @override
  List<List<int>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Int16>();
    return List<List<int>>.generate(samples, (s) {
      final base = s * channels;
      return List<int>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Int16List.fromList(buffer.cast<Int16>().asTypedList(elements));
  }
}

class LSLPullChunkInt32 extends LSLPullChunk<Int32, int> {
  const LSLPullChunkInt32() : super(lsl_pull_chunk_i);

  @override
  Pointer<Int32> allocBuffer(int elements) => allocate<Int32>(elements);

  @override
  List<List<int>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Int32>();
    return List<List<int>>.generate(samples, (s) {
      final base = s * channels;
      return List<int>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Int32List.fromList(buffer.cast<Int32>().asTypedList(elements));
  }
}

class LSLPullChunkInt64 extends LSLPullChunk<Int64, int> {
  const LSLPullChunkInt64() : super(lsl_pull_chunk_l);

  @override
  Pointer<Int64> allocBuffer(int elements) => allocate<Int64>(elements);

  @override
  List<List<int>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Int64>();
    return List<List<int>>.generate(samples, (s) {
      final base = s * channels;
      return List<int>.generate(
        channels,
        (c) => typed[base + c],
        growable: false,
      );
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    return Int64List.fromList(buffer.cast<Int64>().asTypedList(elements));
  }
}

/// String chunk pull (list API only).
///
/// liblsl allocates each returned string; they are released with
/// `lsl_destroy_string` as they are converted. No [TypedData] form exists for
/// variable-length samples.
class LSLPullChunkString extends LSLPullChunk<Pointer<Char>, String> {
  const LSLPullChunkString() : super(lsl_pull_chunk_str);

  @override
  Pointer<Pointer<Char>> allocBuffer(int elements) {
    final buffer = allocate<Pointer<Char>>(elements);
    for (int i = 0; i < elements; i++) {
      buffer[i] = nullPtr<Char>();
    }
    return buffer;
  }

  @override
  List<List<String>> bufferToLists(
    Pointer<NativeType> buffer,
    int samples,
    int channels,
  ) {
    final typed = buffer.cast<Pointer<Char>>();
    return List<List<String>>.generate(samples, (s) {
      final base = s * channels;
      return List<String>.generate(channels, (c) {
        final Pointer<Char> str = typed[base + c];
        if (str.isNullPointer) {
          return '';
        }
        final value = str.cast<Utf8>().toDartString();
        lsl_destroy_string(str);
        typed[base + c] = nullPtr<Char>();
        return value;
      }, growable: false);
    }, growable: false);
  }

  @override
  TypedData bufferToTypedData(Pointer<NativeType> buffer, int elements) {
    throw UnsupportedError(
      'Typed-data chunk access is not available for string streams',
    );
  }
}
