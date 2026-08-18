import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/screens/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = ProfileData(
  firstName: 'John',
  lastName: 'Vane',
  studentId: '2026-00001',
  yearLevel: '4th Year',
  program: 'BS Information Technology',
  schoolEmail: 'john@school.edu',
  personalEmail: 'john@example.com',
  role: 'Student',
);

Future<void> _pumpEditProfile(
  WidgetTester tester,
  Size size, {
  ProfileData profile = _profile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: EditProfileScreen(
        key: ValueKey(profile.role),
        profile: profile,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edit profile fits a portrait phone and enables save on edit',
      (tester) async {
    await _pumpEditProfile(tester, const Size(412, 715));

    expect(find.text('Edit profile'), findsOneWidget);
    expect(
      find.byKey(const Key('edit_profile_back_button')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Personal information').hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'First name').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Save changes'), findsOneWidget);
    var saveButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('save_profile_button')),
    );
    expect(saveButton.onPressed, isNull);
    final saveButtonRect = tester.getRect(
      find.byKey(const Key('save_profile_button')),
    );
    expect(saveButtonRect.top, greaterThan(600));
    expect(saveButtonRect.bottom, lessThanOrEqualTo(715));
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Jonathan',
    );
    await tester.pump();

    saveButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('save_profile_button')),
    );
    expect(saveButton.onPressed, isNotNull);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit profile fits a portrait tablet', (tester) async {
    await _pumpEditProfile(tester, const Size(800, 1280));

    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Account security'), findsNothing);
    expect(find.text('Change password'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login email is immutable and password fields stay off this page',
      (tester) async {
    await _pumpEditProfile(tester, const Size(412, 900));

    final emailField = tester.widget<TextFormField>(
      find.byKey(const Key('edit_school_login_email_field')),
    );
    expect(emailField.enabled, isFalse);
    expect(find.text('Your login email cannot be changed.'), findsOneWidget);
    expect(find.byKey(const Key('change_current_password_field')), findsNothing);
    expect(find.byKey(const Key('change_new_password_field')), findsNothing);
    expect(find.byKey(const Key('change_confirm_password_field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal information fields follow the account type',
      (tester) async {
    const cases = [
      (
        role: 'student',
        accountLabel: 'Current student',
        yearLabel: 'Year level',
        programLabel: 'Program',
      ),
      (
        role: 'former_student',
        accountLabel: 'Former / stopped student',
        yearLabel: 'Year last attended',
        programLabel: 'Program attended',
      ),
      (
        role: 'alumni',
        accountLabel: 'Alumni',
        yearLabel: 'Year graduated',
        programLabel: 'Program',
      ),
      (
        role: 'masters',
        accountLabel: "Master's",
        yearLabel: 'Year graduated / last attended',
        programLabel: "Master's program",
      ),
      (
        role: 'doctorate',
        accountLabel: 'Doctorate',
        yearLabel: 'Year graduated / last attended',
        programLabel: 'Doctorate program',
      ),
    ];

    for (final accountCase in cases) {
      final profile = ProfileData(
        firstName: 'Test',
        lastName: 'Requester',
        studentId: accountCase.role == 'student' ? '2026-00001' : '',
        yearLevel: accountCase.role == 'student' ? '4th Year' : '2025',
        program: 'Information Technology',
        schoolEmail: accountCase.role == 'student' ? 'student@school.edu' : '',
        personalEmail: 'requester@example.com',
        role: accountCase.role,
      );

      await _pumpEditProfile(
        tester,
        const Size(412, 900),
        profile: profile,
      );

      expect(find.text(accountCase.accountLabel), findsWidgets);
      expect(
        find.widgetWithText(TextFormField, accountCase.yearLabel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, accountCase.programLabel),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('edit_academic_year_field')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('edit_program_field')), findsOneWidget);

      if (accountCase.role == 'student') {
        expect(find.byKey(const Key('edit_student_id_field')), findsOneWidget);
        expect(
          find.byKey(const Key('edit_school_login_email_field')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('edit_login_email_field')), findsNothing);
      } else {
        expect(find.byKey(const Key('edit_student_id_field')), findsNothing);
        expect(
          find.byKey(const Key('edit_school_login_email_field')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('edit_login_email_field')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
}
