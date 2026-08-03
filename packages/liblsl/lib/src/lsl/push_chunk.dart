import 'dart:ffi';
import 'dart:typed_data';

import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/ffi/mem.dart';

/// `lsl_push_chunk_*t` — flat data buffer with one timestamp for the chunk
/// (0.0 means "now"; remaining samples are spaced by the sampling rate).
typedef DartLSLPushChunkT<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      double timestamp,
    );

/// `lsl_push_chunk_*tn` — flat data buffer with one timestamp per sample.
typedef DartLSLPushChunkTn<T extends NativeType> =
    int Function(
      lsl_outlet out,
      Pointer<T> data,
      int dataElements,
      Pointer<Double> timestamps,
    );

/// The base class for chunk push operations, one subclass per channel format.
///
/// Data is a flat buffer of `sampleCount * channelCount` values in
/// sample-major order. String streams are not supported (variable-length
/// samples need the `_buf` API family); [LSLMapper.streamPushChunk] rejects
/// them before an instance is ever needed.
abstract class LSLPushChunk<T extends NativeType> {
  final DartLSLPushChunkT<T> _pushT;
  final DartLSLPushChunkTn<T> _pushTn;

  const LSLPushChunk(this._pushT, this._pushTn);

  /// Pushes [elements] values with a single [timestamp] (0.0 = now).
  int pushWithTimestamp(
    lsl_outlet out,
    Pointer<NativeType> data,
    int elements,
    double timestamp,
  ) {
    return _pushT(out, data.cast(), elements, timestamp);
  }

  /// Pushes [elements] values with one timestamp per sample.
  int pushWithTimestamps(
    lsl_outlet out,
    Pointer<NativeType> data,
    int elements,
    Pointer<Double> timestamps,
  ) {
    return _pushTn(out, data.cast(), elements, timestamps);
  }

  /// Allocates a flat native buffer of [elements] values.
  Pointer<T> allocBuffer(int elements);

  /// Writes [flat] (length = elements) into [buffer] element-wise.
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer);

  /// Copies [elements] values from [src] into [buffer] (memmove).
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  );

  /// Whether [data] is the [TypedData] type matching this channel format.
  bool typedDataMatches(TypedData data);

  /// The expected [TypedData] type name, for error messages.
  String get typedDataName;
}

class LSLPushChunkFloat extends LSLPushChunk<Float> {
  const LSLPushChunkFloat() : super(lsl_push_chunk_ft, lsl_push_chunk_ftn);

  @override
  Pointer<Float> allocBuffer(int elements) => allocate<Float>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Float>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Float>().asTypedList(elements).setAll(0, src as Float32List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Float32List;

  @override
  String get typedDataName => 'Float32List';
}

class LSLPushChunkDouble extends LSLPushChunk<Double> {
  const LSLPushChunkDouble() : super(lsl_push_chunk_dt, lsl_push_chunk_dtn);

  @override
  Pointer<Double> allocBuffer(int elements) => allocate<Double>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Double>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Double>().asTypedList(elements).setAll(0, src as Float64List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Float64List;

  @override
  String get typedDataName => 'Float64List';
}

class LSLPushChunkInt8 extends LSLPushChunk<Char> {
  const LSLPushChunkInt8() : super(lsl_push_chunk_ct, lsl_push_chunk_ctn);

  @override
  Pointer<Char> allocBuffer(int elements) => allocate<Char>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Char>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int8>().asTypedList(elements).setAll(0, src as Int8List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int8List;

  @override
  String get typedDataName => 'Int8List';
}

class LSLPushChunkInt16 extends LSLPushChunk<Int16> {
  const LSLPushChunkInt16() : super(lsl_push_chunk_st, lsl_push_chunk_stn);

  @override
  Pointer<Int16> allocBuffer(int elements) => allocate<Int16>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int16>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int16>().asTypedList(elements).setAll(0, src as Int16List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int16List;

  @override
  String get typedDataName => 'Int16List';
}

class LSLPushChunkInt32 extends LSLPushChunk<Int32> {
  const LSLPushChunkInt32() : super(lsl_push_chunk_it, lsl_push_chunk_itn);

  @override
  Pointer<Int32> allocBuffer(int elements) => allocate<Int32>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int32>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int32>().asTypedList(elements).setAll(0, src as Int32List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int32List;

  @override
  String get typedDataName => 'Int32List';
}

class LSLPushChunkInt64 extends LSLPushChunk<Int64> {
  const LSLPushChunkInt64() : super(lsl_push_chunk_lt, lsl_push_chunk_ltn);

  @override
  Pointer<Int64> allocBuffer(int elements) => allocate<Int64>(elements);

  @override
  @pragma('vm:prefer-inline')
  void flatListToBuffer(Iterable<dynamic> flat, Pointer<NativeType> buffer) {
    final typed = buffer.cast<Int64>();
    int i = 0;
    for (final value in flat) {
      typed[i++] = value;
    }
  }

  @override
  @pragma('vm:prefer-inline')
  void typedDataToBuffer(
    TypedData src,
    Pointer<NativeType> buffer,
    int elements,
  ) {
    buffer.cast<Int64>().asTypedList(elements).setAll(0, src as Int64List);
  }

  @override
  bool typedDataMatches(TypedData data) => data is Int64List;

  @override
  String get typedDataName => 'Int64List';
}
