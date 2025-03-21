import 'dart:ffi';
import 'package:liblsl/liblsl.dart';

typedef DartLslPushSample<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data);

// Create a wrapper class to handle the different types
class LslPushSample<T extends NativeType> {
  final DartLslPushSample<T> _pushFn;

  const LslPushSample(this._pushFn);

  int call(lsl_outlet out, Pointer<T> data) {
    return _pushFn(out, data);
  }
}
