extension MapIndexed<T> on Iterable<T> {
  /// Maps each element of the iterable to a new value, providing the index of
  /// the element in the original iterable.
  ///
  /// Example:
  /// ```dart
  /// final list = [1, 2, 3];
  /// final result = list.mapIndexed((index, item) => item * index);
  /// print(result); // Output: [0, 2, 6]
  /// ```
  Iterable<E> mapIndexed<E>(E Function(int index, T item) f) sync* {
    int length = this.length;

    for (int index = 0; index < length; index++) {
      T item = elementAt(index);
      yield f(index, item);
      index = index + 1;
    }
  }
}
