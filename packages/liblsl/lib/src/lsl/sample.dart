import 'dart:ffi' show Pointer, NativeType;

export 'package:lsl_core/lsl_core.dart' show LSLSample;

@pragma('vm:deeply-immutable')
final class LSLSamplePointer<T extends NativeType> {
  final double timestamp;
  final int errorCode;
  final int pointerAddress;

  const LSLSamplePointer(this.timestamp, this.errorCode, this.pointerAddress);
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
