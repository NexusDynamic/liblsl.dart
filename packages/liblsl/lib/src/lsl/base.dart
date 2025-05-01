import 'dart:async';
import 'dart:ffi';
import 'package:liblsl/src/ffi/mem.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/native_liblsl.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Base class for LSL objects.
///
/// This class is used to manage the lifecycle of LSL objects to abstract
/// the complexity away from the user.
abstract class LSLObj {
  /// A list of allocated pointers.
  final List<Pointer> _allocated = [];
  bool _created = false;
  bool _destroyed = false;

  /// Creates the object.
  ///
  /// This method should be overridden by subclasses to create the object.
  /// It should call [addAlloc] or [addAllocList] to add any allocated pointers
  /// to the [_allocated] list that need to be freed when the object is
  /// destroyed.
  @mustCallSuper
  @mustBeOverridden
  FutureOr<LSLObj> create() {
    if (_created) {
      throw LSLException('Object already created');
    }
    if (_destroyed) {
      throw LSLException('Object already destroyed');
    }
    _created = true;
    return this;
  }

  /// Adds a pointer to the list of allocated pointers.
  void addAlloc(Pointer arg) {
    _allocated.add(arg);
  }

  /// Adds a list of pointers to the list of allocated pointers.
  void addAllocList(List<Pointer> args) {
    _allocated.addAll(args);
  }

  /// Frees all allocated pointers.
  void freeArgs() {
    for (final arg in _allocated) {
      arg.free();
    }
    _allocated.clear();
  }

  /// Destroys the object.
  ///
  /// This method should be overridden by subclasses to destroy the object.
  /// This super method handles the freeing of allocated pointers.
  @mustCallSuper
  @mustBeOverridden
  void destroy() {
    _destroyed = true;
    freeArgs();
  }

  /// Checks if the error code is an error.
  ///
  /// This method checks if the error code is not equal to
  /// [lsl_error_code_t.lsl_no_error].
  static bool error(int code) {
    final e = lsl_error_code_t.fromValue(code);
    return e != lsl_error_code_t.lsl_no_error;
  }

  /// Whether the object has been created.
  bool get created => _created;

  /// Whether the object has been destroyed.
  bool get destroyed => _destroyed;
}
