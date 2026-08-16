import 'package:capstone_project/screens/data_consent_screen.dart';
import 'package:capstone_project/screens/pending_screen.dart';
import 'package:capstone_project/screens/register_screen.dart';
import 'package:capstone_project/screens/request_detail_screen.dart';
import 'package:capstone_project/screens/request_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _setPhoneSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) {
  return ScreenUtilInit(
    designSize: const Size(412, 715),
    builder: (_, __) => MaterialApp(home: home),
  );
}

Widget _launcher(Widget destination) {
  return _app(
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open_screen'),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => destination),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openAndReturn(
  WidgetTester tester, {
  required Widget screen,
  required Key backButtonKey,
}) async {
  await tester.pumpWidget(_launcher(screen));
  await tester.tap(find.byKey(const Key('open_screen')));
  await tester.pumpAndSettle();

  expect(find.byKey(backButtonKey), findsOneWidget);
  expect(tester.takeException(), isNull);

  await tester.tap(find.byKey(backButtonKey));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('open_screen')), findsOneWidget);
}

void main() {
  testWidgets('request flow screens have working phone back buttons',
      (tester) async {
    await _setPhoneSize(tester);

    await _openAndReturn(
      tester,
      screen: const DataConsentScreen(),
      backButtonKey: const Key('consent_back_button'),
    );
    await _openAndReturn(
      tester,
      screen: const RequestFormScreen(),
      backButtonKey: const Key('request_form_back_button'),
    );
    await _openAndReturn(
      tester,
      screen: const RegisterScreen(),
      backButtonKey: const Key('registration_back_button'),
    );
  });

  testWidgets('request details fit long values on a narrow phone',
      (tester) async {
    await _setPhoneSize(tester);

    await tester.pumpWidget(
      _app(
        RequestDetailsScreen(
          request: PendingRequest(
            docName:
                'Certified True Copy of a Very Long Academic Document Name',
            purpose: 'Employment and international credential verification',
            dateCreated: DateTime(2026, 8, 3, 14, 30),
            status: 'PENDING FOR PAYMENT',
            documentPrice: 600,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('request_detail_back_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
