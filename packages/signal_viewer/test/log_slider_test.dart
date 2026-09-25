import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signal_viewer/src/model/stream_info.dart';
import 'package:signal_viewer/src/ui/widgets/widgets.dart';

void main() {
  group('prettyUnit', () {
    test('maps spelled-out units to symbols', () {
      expect(prettyUnit('microvolts'), 'µV');
      expect(prettyUnit('uV'), 'µV');
      expect(prettyUnit('Millivolts'), 'mV');
      expect(prettyUnit(' volts '), 'V');
    });

    test('leaves unknown units alone', () {
      expect(prettyUnit('g'), 'g');
      expect(prettyUnit('a.u.'), 'a.u.');
      expect(prettyUnit(''), '');
    });
  });

  testWidgets('a long unit does not hide the number', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 296,
              child: LogSlider(
                value: 50,
                min: 0.1,
                max: 1e6,
                suffix: 'some very long unit name/div',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final field = tester.getSize(find.byType(TextField));
    expect(field.width, 80);
    expect(find.text('50'), findsOneWidget);
    // The unit is shown beside the box, cut short if it has to be.
    final unit = tester.getSize(find.text('some very long unit name/div'));
    expect(unit.width, lessThanOrEqualTo(64));
  });
}
