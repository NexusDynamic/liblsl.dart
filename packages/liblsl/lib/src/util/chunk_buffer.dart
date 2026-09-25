import 'dart:ffi';

import 'package:liblsl/src/ffi/mem.dart';

/// A reusable native buffer for chunk transfers (data + per-sample
/// timestamps + error code), grown on demand.
///
/// One instance is held per outlet/inlet, lazily allocated on the first chunk
/// operation so users who never touch chunks pay nothing. Growth frees and
/// reallocates at the next power of two to amortize repeated larger pulls.
class LSLChunkBuffer {
  /// Number of channels per sample; fixed for the stream's lifetime.
  final int channels;

  final Pointer<NativeType> Function(int elements) _allocData;

  Pointer<NativeType> _data = nullptr;
  Pointer<Double> _timestamps = nullptr;
  final Pointer<Int32> ec = allocate<Int32>();

  int _capacitySamples = 0;
  bool _freed = false;

  LSLChunkBuffer(this.channels, this._allocData);

  Pointer<NativeType> get data => _data;
  Pointer<Double> get timestamps => _timestamps;
  int get capacitySamples => _capacitySamples;
  bool get freed => _freed;

  /// Ensures room for [samples] frames of [channels] values each.
  void ensureCapacity(int samples) {
    if (_freed) {
      throw StateError('LSLChunkBuffer already freed');
    }
    if (samples <= _capacitySamples) {
      return;
    }
    int newCapacity = _capacitySamples < 16 ? 16 : _capacitySamples;
    while (newCapacity < samples) {
      newCapacity *= 2;
    }
    if (!_data.isNullPointer) {
      _data.free();
    }
    if (!_timestamps.isNullPointer) {
      _timestamps.free();
    }
    _data = _allocData(newCapacity * channels);
    _timestamps = allocate<Double>(newCapacity);
    if (_data.isNullPointer || _timestamps.isNullPointer) {
      throw StateError('Failed to allocate chunk buffer');
    }
    _capacitySamples = newCapacity;
  }

  void free() {
    if (_freed) {
      return;
    }
    _freed = true;
    if (!_data.isNullPointer) {
      _data.free();
      _data = nullptr;
    }
    if (!_timestamps.isNullPointer) {
      _timestamps.free();
      _timestamps = nullptr;
    }
    ec.free();
    _capacitySamples = 0;
  }
}
