import 'package:capstone_project/screens/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpChangePassword(
  WidgetTester tester, {
  ChangePasswordHandler? handler,
}) async {
  tester.view.physicalSize = const Size(412, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: ChangePasswordScreen(changePasswordHandler: handler),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('change password requires the current password', (tester) async {
    await _pumpChangePassword(tester);

    expect(find.text('Change password'), findsWidgets);
    expect(find.text('Protect your account'), findsNothing);
    expect(find.text('8-72 characters'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('change_new_password_field')),
      'SecurePass1!',
    );
    await tester.enterText(
      find.byKey(const Key('change_confirm_password_field')),
      'SecurePass1!',
    );
    final submit = find.byKey(const Key('change_password_submit_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('Enter your current password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('change password submits current and new passwords',
      (tester) async {
    String? receivedCurrentPassword;
    String? receivedNewPassword;
    await _pumpChangePassword(
      tester,
      handler: (currentPassword, newPassword) async {
        receivedCurrentPassword = currentPassword;
        receivedNewPassword = newPassword;
      },
    );

    await tester.enterText(
      find.byKey(const Key('change_current_password_field')),
      'CurrentPass1!',
    );
    await tester.enterText(
      find.byKey(const Key('change_new_password_field')),
      'SecurePass2!',
    );
    await tester.enterText(
      find.byKey(const Key('change_confirm_password_field')),
      'SecurePass2!',
    );
    final submit = find.byKey(const Key('change_password_submit_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(receivedCurrentPassword, 'CurrentPass1!');
    expect(receivedNewPassword, 'SecurePass2!');
    expect(find.text('Password changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
