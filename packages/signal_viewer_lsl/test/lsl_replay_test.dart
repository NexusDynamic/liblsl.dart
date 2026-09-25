import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/signal_viewer.dart';
import 'package:signal_viewer_lsl/signal_viewer_lsl.dart';
import 'package:signal_viewer_xdf/signal_viewer_xdf.dart';

/// An outlet that keeps what is pushed, as a bridge's would send it on.
class _Outlet implements LslOutlet {
  @override
  final LslOutletSpec spec;
  final times = <double>[];
  final values = <double>[];
  final strings = <String>[];
  bool closed = false;

  _Outlet(this.spec);

  @override
  Future<void> push(Float32List values, Float64List times) async {
    this.values.addAll(values);
    this.times.addAll(times);
  }

  @override
  Future<void> pushStrings(List<String> values, List<double> times) async {
    strings.addAll(values);
    this.times.addAll(times);
  }

  @override
  Future<bool> hasConsumers() async => true;

  @override
  Future<void> close() async => closed = true;
}

void main() {
  testWidgets('a recording replays one stream through an outlet factory', (
    tester,
  ) async {
    final state = AppState(
      Preferences(),
      providers: [XdfProvider()],
      config: const ViewerConfig(title: 'Test', heading: 'Test'),
    );
    await tester.pumpWidget(MaterialApp(home: MainWindow(state: state)));
    await tester.runAsync(
      () => state.openFiles([
        fileAtPath('../xdf/test/fixtures/clock_resets.xdf')!,
      ]),
    );
    final session = state.sessions.single as XdfSession;
    await tester.runAsync(() => session.file.indexed);
    for (var i = 0; i < 400 && state.tabs.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final eeg = session.streams.firstWhere((s) => s.kind == Kind.eeg);
    final outlets = <_Outlet>[];

    final r = await tester.runAsync(
      () => LslReplayForward.start(
        session,
        eeg,
        name: 'replayed',
        from: 0,
        create: (spec) async => (outlets..add(_Outlet(spec))).last,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    // Only the chosen stream, under the chosen name.
    expect(outlets, hasLength(1));
    final o = outlets.single;
    expect(o.spec.name, 'replayed');
    expect(o.spec.channelCount, eeg.channelCount);
    expect(o.times, isNotEmpty);
    expect(r!.sent, o.times.length);
    expect(o.values.length, o.times.length * eeg.channelCount);

    await tester.runAsync(r.close);
    expect(o.closed, isTrue);
    await tester.runAsync(() => state.closeSession(session));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
