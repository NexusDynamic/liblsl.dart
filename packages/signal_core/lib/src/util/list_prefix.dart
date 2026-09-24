import 'dart:collection';

/// The first [length] elements of an append-only list, read-only: a
/// snapshot that costs nothing to take.
class ListPrefix<T> extends ListBase<T> {
  final List<T> _list;
  final int _length;

  ListPrefix(this._list, this._length);

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Unmodifiable list');

  @override
  T operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    return _list[index];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Unmodifiable list');
}
