import 'dart:ffi';

import 'package:liblsl/src/ffi/mem.dart';

/// A Reusable buffer for LSL samples to avoid memory allocation overhead.
abstract class LSLReusableBuffer<T extends NativeType> {
  /// The buffer to store the sample.
  final Pointer<T> buffer;

  /// Holds the size of the buffer in number of elements, this often
  /// corresponds to the number of channels in the sample.
  /// But for chunked data, this is the number of chunks times the number of
  /// channels.
  final int capacity;

  /// The error code pointer.
  final Pointer<Int32> ec = allocate<Int32>();

  /// Creates a reusable buffer of the given capacity.
  /// @param [capacity] The capacity of the buffer in number of elements.
  /// @param [buffer] The buffer to store the sample.
  LSLReusableBuffer(this.capacity, this.buffer) {
    if (buffer.isNullPointer && (this is! LSLReusableBufferVoid)) {
      throw ArgumentError('Error allocating buffer of type ${T.runtimeType}');
    }
  }

  void free() {
    buffer.free();
    ec.free();
  }
}

class LSLReusableBufferFloat extends LSLReusableBuffer<Float> {
  /// Creates a reusable Float buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferFloat(int capacity)
    : super(capacity, allocate<Float>(capacity));
}

class LSLReusableBufferDouble extends LSLReusableBuffer<Double> {
  /// Creates a reusable Double buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferDouble(int capacity)
    : super(capacity, allocate<Double>(capacity));
}

class LSLReusableBufferInt8 extends LSLReusableBuffer<Char> {
  /// Creates a reusable Int8 buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferInt8(int capacity)
    : super(capacity, allocate<Char>(capacity));
}

class LSLReusableBufferInt16 extends LSLReusableBuffer<Int16> {
  /// Creates a reusable Int16 buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferInt16(int capacity)
    : super(capacity, allocate<Int16>(capacity));
}

class LSLReusableBufferInt32 extends LSLReusableBuffer<Int32> {
  /// Creates a reusable Int32 buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferInt32(int capacity)
    : super(capacity, allocate<Int32>(capacity));
}

class LSLReusableBufferInt64 extends LSLReusableBuffer<Int64> {
  /// Creates a reusable Int64 buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferInt64(int capacity)
    : super(capacity, allocate<Int64>(capacity));
}

class LSLReusableBufferString extends LSLReusableBuffer<Pointer<Char>> {
  /// Creates a reusable String buffer of the given capacity.
  /// see [LSLReusableBuffer]
  LSLReusableBufferString(int capacity)
    : super(capacity, allocate<Pointer<Char>>(capacity));
}

class LSLReusableBufferVoid extends LSLReusableBuffer<Void> {
  /// Creates a reusable Void buffer of the given capacity.
  /// This differs from the other buffers in that it does not allocate
  /// memory for the buffer, but instead uses a null pointer.
  /// see [LSLReusableBuffer]
  LSLReusableBufferVoid(int capacity) : super(capacity, nullPtr<Void>());
}
