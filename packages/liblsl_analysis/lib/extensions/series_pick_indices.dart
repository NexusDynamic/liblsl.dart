import 'package:dartframe/dartframe.dart';

extension SeriesPickIndices on Series {
  Series indices(List<dynamic> indices) {
    List<dynamic> selectedData = [];

    for (int i = 0; i < indices.length; i++) {
      if (indices[i]) {
        selectedData.add(data[i]);
      }
    }
    return Series(selectedData, name: name);
  }
}
