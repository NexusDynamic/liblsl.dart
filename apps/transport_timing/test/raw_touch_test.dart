import 'dart:ui' show PointerChange, PointerData, PointerDataPacket;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_timing/src/ui/raw_touch.dart';

void main() {
  testWidgets('a touch is reported from the packet, ahead of the framework', (
    tester,
  ) async {
    // What happened, in order.
    final seen = <String>[];
    final touches = <(double, Duration)>[];
    var clock = 100.0;

    final dispatcher = tester.binding.platformDispatcher;
    final framework = dispatcher.onPointerDataPacket;

    await tester.pumpWidget(
      RawTouchListener(
        // Moves on with every reading: one packet, one reading.
        clock: () => clock++,
        onTouch: (heard, timeStamp) {
          seen.add('raw');
          touches.add((heard, timeStamp));
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => seen.add('framework'),
          child: const SizedBox.expand(),
        ),
      ),
    );
    expect(dispatcher.onPointerDataPacket, isNot(framework));

    PointerData pointer(
      PointerChange change,
      int microseconds, {
      int device = 1,
      bool synthesized = false,
    }) => PointerData(
      change: change,
      timeStamp: Duration(microseconds: microseconds),
      device: device,
      // The framework tells presses apart by this.
      pointerIdentifier: device,
      physicalX: 10,
      physicalY: 10,
      synthesized: synthesized,
    );
    void send(List<PointerData> data) =>
        dispatcher.onPointerDataPacket!(PointerDataPacket(data: data));

    send([pointer(PointerChange.add, 4000)]);
    expect(touches, isEmpty);

    send([pointer(PointerChange.down, 5000)]);
    expect(touches, [(101.0, const Duration(microseconds: 5000))]);
    // The framework had the same packet, once the touch was dealt with.
    expect(seen, ['raw', 'framework']);

    // Not a touch: movement, release, and what the engine made up.
    send([pointer(PointerChange.move, 6000)]);
    send([pointer(PointerChange.up, 7000)]);
    send([pointer(PointerChange.down, 8000, synthesized: true)]);
    send([pointer(PointerChange.up, 8500, synthesized: true)]);
    expect(touches, hasLength(1));

    // Two fingers in one packet share the reading of the clock.
    send([pointer(PointerChange.add, 8900, device: 2)]);
    send([
      pointer(PointerChange.down, 9000),
      pointer(PointerChange.down, 9001, device: 2),
    ]);
    expect(touches.skip(1).map((t) => t.$1).toSet(), hasLength(1));
    expect(touches, hasLength(3));
    send([
      pointer(PointerChange.up, 9500),
      pointer(PointerChange.up, 9501, device: 2),
    ]);

    // Gone with the widget.
    await tester.pumpWidget(const SizedBox());
    expect(dispatcher.onPointerDataPacket, framework);
    expect(tester.takeException(), isNull);
  });
}
