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
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const MaterialApp(home: EditProfileScreen(profile: _profile)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edit profile fits a portrait phone and enables save on edit',
      (tester) async {
    await _pumpEditProfile(tester, const Size(412, 715));

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('No changes to save'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Jonathan',
    );
    await tester.pump();

    final saveButton = tester.widget<ElevatedButton>(
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
    expect(find.text('Password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
