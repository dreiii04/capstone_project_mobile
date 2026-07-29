import 'package:capstone_project/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpRegister(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      routes: {'/login': (_) => const SizedBox()},
      home: const RegisterScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAccountType(
  WidgetTester tester,
  String accountType,
) async {
  await tester.tap(find.byKey(const Key('account_type_field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(accountType).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('account type offers only former student and alumni',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    expect(find.text('Current student'), findsNothing);

    await _selectAccountType(tester, 'Former student');
    expect(find.text('Year Last Attended'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text('School email'), findsNothing);

    await _selectAccountType(tester, 'Alumni');
    expect(find.text('Year Graduated'), findsOneWidget);
    expect(find.text('Student ID'), findsNothing);
    expect(find.text('School email'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank registration shows inline validation errors',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    final submit = find.byKey(const Key('create_account_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Select your account type to continue'), findsOneWidget);
    expect(find.text('Enter your first name'), findsOneWidget);
    expect(find.text('Enter your last name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Select your program'), findsOneWidget);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(find.text('Confirm your password'), findsOneWidget);
    expect(
      find.text('Accept the Terms and Conditions to continue'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid email and weak password are explained inline',
      (tester) async {
    await _pumpRegister(tester, const Size(800, 1280));

    await _selectAccountType(tester, 'Alumni');
    await tester.enterText(
      find.byKey(const Key('first_name_field')),
      'Anne-Marie',
    );
    await tester.enterText(
      find.byKey(const Key('last_name_field')),
      "O'Connor",
    );
    await tester.enterText(
      find.byKey(const Key('registration_email_field')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const Key('registration_password_field')),
      'weak',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password_field')),
      'different',
    );

    final submit = find.byKey(const Key('create_account_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(
      find.text(
        'Use 8-72 chars with upper/lowercase, number, symbol, and no spaces',
      ),
      findsOneWidget,
    );
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
