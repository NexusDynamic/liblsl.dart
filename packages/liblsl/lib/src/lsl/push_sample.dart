import 'dart:ffi';
import 'package:liblsl/native_liblsl.dart';

/// Generalized description of the lsl_push_sample_* functions.
typedef DartLslPushSample<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data);

/// The base class for all LSL push sample types.
class LslPushSample<T extends NativeType> {
  final DartLslPushSample<T> _pushFn;

  const LslPushSample(this._pushFn);

  int call(lsl_outlet out, Pointer<T> data) {
    return _pushFn(out, data);
  }
}
