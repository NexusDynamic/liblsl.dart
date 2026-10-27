import 'dart:typed_data';

import 'package:signal_viewer/signal_viewer.dart';

import 'sd_target.dart';

SdTarget create(String name) => _MemoryTarget(name);

class _MemoryTarget implements SdTarget, Sink<List<int>> {
  final String name;
  final _out = BytesBuilder(copy: false);
  _MemoryTarget(this.name);

  @override
  Sink<List<int>> get sink => this;

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void close() {}

  @override
  Future<ByteSourceSpec> finish() async =>
      ByteSourceSpec.bytes(_out.takeBytes(), name: name);
}
