import 'dart:ffi' show Pointer, NativeType;

/// A representation of a sample.
///
/// This class represents both samples pulled from an inlet, and in future
/// versions, samples pushed to an outlet.
class LSLSample<T> {
  final List<T> data;
  final double timestamp;
  final int errorCode;

  LSLSample(this.data, this.timestamp, this.errorCode);

  T operator [](int index) {
    return data[index];
  }

  int get length {
    return data.length;
  }

  bool get isEmpty {
    return data.isEmpty;
  }

  bool get isNotEmpty {
    return data.isNotEmpty;
  }

  @override
  String toString() {
    return 'LSLSample{data: $data, timestamp: $timestamp, errorCode: $errorCode}';
  }
}

class LSLSamplePointer<T extends NativeType> {
  final double timestamp;
  final int errorCode;
  final int pointerAddress;

  LSLSamplePointer(this.timestamp, this.errorCode, this.pointerAddress);
  Pointer<T> get pointer {
    return Pointer<T>.fromAddress(pointerAddress);
  }

  @override
  String toString() {
    return 'LSLSamplePointer{timestamp: $timestamp, errorCode: $errorCode, pointerAddress: $pointerAddress}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LSLSamplePointer<T>) return false;
    return timestamp == other.timestamp &&
        errorCode == other.errorCode &&
        pointerAddress == other.pointerAddress;
  }

  @override
  int get hashCode {
    return timestamp.hashCode ^ errorCode.hashCode ^ pointerAddress.hashCode;
  }
}
