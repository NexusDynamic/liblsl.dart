/// The connect screen's one piece of real logic: which ICE servers a direct
/// session is given, and what it refuses to be given.
///
/// Worth a test because the field is the difference between a session that
/// crosses a NAT and one that quietly gathers no usable candidates, and
/// because the TURN rule is a design decision rather than a typo guard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peer_coordinator_example/src/ui/connect_page.dart';

void main() {
  const stunLabel = 'STUN servers (optional)';

  /// Pumps the page with the direct transport selected.
  Future<void> pumpDirect(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectPage()));
    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
  }

  testWidgets('the STUN field belongs to the direct transport alone', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectPage()));
    // Relay goes through the hub, so ICE servers would mean nothing.
    expect(find.text(stunLabel), findsNothing);

    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
    expect(find.text(stunLabel), findsOneWidget);
  });

  testWidgets('empty is valid — that is the LAN case', (tester) async {
    await pumpDirect(tester);
    await tester.enterText(find.widgetWithText(TextFormField, stunLabel), '');
    await tester.tap(find.text('Join'));
    await tester.pump();

    expect(find.textContaining('stun:'), findsNothing);
  });

  testWidgets(
    'TURN is refused, because it puts a relay back on the data path',
    (tester) async {
      await pumpDirect(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, stunLabel),
        'turn:turn.example.com:3478',
      );
      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(
        find.text('TURN relays the data — use Relay mode instead'),
        findsOneWidget,
      );
    },
  );

  testWidgets('anything that is not a STUN URL is refused', (tester) async {
    await pumpDirect(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, stunLabel),
      'stun.l.google.com:19302',
    );
    await tester.tap(find.text('Join'));
    await tester.pump();

    expect(find.textContaining('Must start with stun:'), findsOneWidget);
  });

  testWidgets('the globe button fills in a usable server', (tester) async {
    await pumpDirect(tester);
    await tester.tap(find.byIcon(Icons.public));
    await tester.pumpAndSettle();

    expect(find.text('stun:stun.l.google.com:19302'), findsOneWidget);
  });
}
