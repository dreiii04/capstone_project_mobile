import 'package:capstone_project/screens/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pending card fits a portrait tablet without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: PendingScreen(
          requestList: [
            PendingRequest(
              docName: 'Transcript of Records (TOR)',
              purpose: 'Employment',
              dateCreated: DateTime(2026, 7, 27, 12, 31),
              status: 'PENDING FOR PAYMENT',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transcript of Records (TOR)'), findsOneWidget);
    expect(find.text('PENDING FOR PAYMENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
