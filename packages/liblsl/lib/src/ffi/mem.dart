// Original source:
// https://github.com/simolus3/sqlite3.dart/blob/main/sqlite3/lib/src/ffi/memory.dart

// MIT License

// Copyright (c) 2020 Simon Binder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi;

const allocate = ffi.malloc;

/// Loads a null-pointer with a specified type.
///
/// The [nullptr] getter from `dart:ffi` can be slow due to being a
/// `Pointer<Null>` on which the VM has to perform runtime type checks. See also
/// https://github.com/dart-lang/sdk/issues/39488
@pragma('vm:prefer-inline')
Pointer<T> nullPtr<T extends NativeType>() => nullptr.cast<T>();

Pointer<Void> _freeImpl(Pointer<Void> ptr) {
  ptr.free();
  return nullPtr();
}

/// Pointer to a function that frees memory we allocated.
///
/// This corresponds to `void(*)(void*)` arguments found in sqlite.
final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
    freeFunctionPtr = Pointer.fromFunction(_freeImpl);

extension FreePointerExtension on Pointer {
  void free() => allocate.free(this);
}

Pointer<Uint8> allocateBytes(List<int> bytes, {int additionalLength = 0}) {
  final ptr = allocate.allocate<Uint8>(bytes.length + additionalLength);

  ptr.asTypedList(bytes.length + additionalLength)
    ..setAll(0, bytes)
    ..fillRange(bytes.length, bytes.length + additionalLength, 0);

  return ptr;
}

extension Utf8Utils on Pointer<Int8> {
  int get _length {
    final asBytes = cast<Uint8>();
    var length = 0;

    for (; asBytes[length] != 0; length++) {}
    return length;
  }

  String? readNullableString([int? length]) {
    return isNullPointer ? null : readString(length);
  }

  String readString([int? length]) {
    final resolvedLength = length ??= _length;
    final dartList = cast<Uint8>().asTypedList(resolvedLength);

    return utf8.decode(dartList);
  }

  static Pointer<Int8> allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1).cast();
  }
}

extension PointerUtils on Pointer<NativeType> {
  bool get isNullPointer => address == 0;

  Uint8List copyRange(int length) {
    final list = Uint8List(length);
    list.setAll(0, cast<Uint8>().asTypedList(length));
    return list;
  }
}
