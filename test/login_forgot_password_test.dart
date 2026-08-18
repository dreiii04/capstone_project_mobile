import 'package:capstone_project/screens/forgot_password_screen.dart';
import 'package:capstone_project/screens/home_screen.dart';
import 'package:capstone_project/screens/login_screen.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) {
  return MaterialApp(
    routes: {
      '/login': (_) => const SizedBox(key: Key('login_route')),
      '/forgot': (_) => const PasswordScreen(),
      '/register': (_) => const SizedBox(),
    },
    home: home,
  );
}

void main() {
  testWidgets('login is responsive and validates credentials inline',
      (tester) async {
    await _setSize(tester, const Size(412, 715));
    await tester.pumpWidget(_app(const LogInScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();
    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'invalid-email',
    );
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login normalizes email and preserves the entered password',
      (tester) async {
    await _setSize(tester, const Size(800, 1280));
    String? receivedEmail;
    String? receivedPassword;

    await tester.pumpWidget(
      _app(
        LogInScreen(
          loginHandler: (email, password) async {
            receivedEmail = email;
            receivedPassword = password;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'USER@Example.COM',
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'Strong1!',
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(receivedEmail, 'user@example.com');
    expect(receivedPassword, 'Strong1!');
    expect(find.text('Unable to log in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login displays the centralized API account-status message',
      (tester) async {
    await _setSize(tester, const Size(412, 715));
    await tester.pumpWidget(
      _app(
        LogInScreen(
          loginHandler: (_, __) async {
            throw Exception(
              'This account has been deactivated. Contact the administrator.',
            );
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'Strong1!',
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Unable to log in'), findsOneWidget);
    expect(
      find.text(
        'This account has been deactivated. Contact the administrator.',
      ),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password reveals OTP only after sending a code',
      (tester) async {
    await _setSize(tester, const Size(412, 715));
    String? requestedEmail;
    String? verifiedEmail;
    String? verifiedOtp;
    String? verifiedChallengeToken;

    await tester.pumpWidget(
      _app(
        PasswordScreen(
          otpRequester: (email) async {
            requestedEmail = email;
            return OtpChallenge(
              challengeToken: 'password-reset-challenge',
              developmentOtp: '123456',
            );
          },
          otpVerifier: (email, otp, challengeToken) async {
            verifiedEmail = email;
            verifiedOtp = otp;
            verifiedChallengeToken = challengeToken;
            return 'reset-token';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reset_otp_field')), findsNothing);
    await tester.tap(find.byKey(const Key('send_reset_code_button')));
    await tester.pump();
    expect(find.text('Enter your registered email'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgot_email_field')),
      'USER@Example.COM',
    );
    await tester.tap(find.byKey(const Key('send_reset_code_button')));
    await tester.pumpAndSettle();

    expect(requestedEmail, 'user@example.com');
    expect(find.byKey(const Key('reset_otp_field')), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('reset_otp_field')),
      '123456',
    );
    await tester.ensureVisible(
      find.byKey(const Key('verify_reset_code_button')),
    );
    await tester.tap(find.byKey(const Key('verify_reset_code_button')));
    await tester.pumpAndSettle();

    expect(verifiedEmail, 'user@example.com');
    expect(verifiedOtp, '123456');
    expect(verifiedChallengeToken, 'password-reset-challenge');
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset password explains weak and mismatched passwords',
      (tester) async {
    await _setSize(tester, const Size(800, 1280));
    await tester.pumpWidget(
      _app(
        ResetPasswordScreen(
          resetToken: 'reset-token',
          passwordResetHandler: (_, __) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new_password_field')),
      'weak',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_new_password_field')),
      'different',
    );
    await tester.tap(find.byKey(const Key('reset_password_button')));
    await tester.pump();

    expect(
      find.text('Complete all password requirements below'),
      findsOneWidget,
    );
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
