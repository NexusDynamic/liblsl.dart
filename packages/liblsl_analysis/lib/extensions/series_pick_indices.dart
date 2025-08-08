import 'package:dartframe/dartframe.dart';

extension SeriesPickIndices on Series {
  /// Select data using boolean indices
  Series indices(List<dynamic> booleanIndices) {
    List<dynamic> selectedData = [];

    for (int i = 0; i < booleanIndices.length && i < data.length; i++) {
      if (booleanIndices[i] == true) {
        selectedData.add(data[i]);
      }
    }
    return Series(selectedData, name: name);
  }

  /// Get actual integer indices where condition is true
  List<int> getIndicesWhere(bool Function(dynamic) condition) {
    List<int> indices = [];
    for (int i = 0; i < data.length; i++) {
      if (condition(data[i])) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// Select data using integer indices
  Series selectByIndices(List<int> indices) {
    List<dynamic> selectedData = [];
    for (final index in indices) {
      if (index < data.length) {
        selectedData.add(data[index]);
      }
    }
    return Series(selectedData, name: name);
  }
}
