import 'dart:ffi';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/liblsl.dart';

abstract class LSLObj {
  final List<Pointer> _allocatedArgs = [];
  bool _created = false;
  bool _destroyed = false;
  LSLObj create() {
    if (_created) {
      throw LSLException('Object already created');
    }
    if (_destroyed) {
      throw LSLException('Object already destroyed');
    }
    _created = true;
    return this;
  }

  void addAlloc(Pointer arg) {
    _allocatedArgs.add(arg);
  }

  void addAllocList(List<Pointer> args) {
    _allocatedArgs.addAll(args);
  }

  void freeArgs() {
    for (final arg in _allocatedArgs) {
      arg.free();
    }
    _allocatedArgs.clear();
  }

  void destroy() {
    _destroyed = true;
    freeArgs();
  }

  static bool error(int code) {
    final e = lsl_error_code_t.fromValue(code);
    return e != lsl_error_code_t.lsl_no_error;
  }

  bool get created => _created;
  bool get destroyed => _destroyed;
}
