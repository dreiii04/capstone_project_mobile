import 'package:capstone_project/screens/register_screen.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpRegister(
  WidgetTester tester,
  Size size, {
  Widget register = const RegisterScreen(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      routes: {'/login': (_) => const SizedBox()},
      home: register,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDropdown(
  WidgetTester tester,
  Key fieldKey,
  String option,
) async {
  final field = find.byKey(fieldKey);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _selectStudentStatus(
  WidgetTester tester,
  String status,
) =>
    _selectDropdown(tester, const Key('student_status_field'), status);

Future<void> _selectEducationalLevel(
  WidgetTester tester,
  String status,
  String level,
) =>
    _selectDropdown(tester, ValueKey('educational_level_$status'), level);

void main() {
  testWidgets('academic fields stay hidden until a student status is selected',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    expect(find.byKey(const Key('first_name_field')), findsOneWidget);
    expect(find.byKey(const Key('last_name_field')), findsOneWidget);
    expect(find.byKey(const Key('registration_email_field')), findsOneWidget);
    expect(
        find.byKey(const Key('registration_password_field')), findsOneWidget);
    expect(find.byKey(const Key('confirm_password_field')), findsOneWidget);
    expect(find.text('Last Educational Level Attended'), findsNothing);
    expect(find.text('Highest Educational Level Completed'), findsNothing);
    expect(find.byKey(const Key('program_field')), findsNothing);
    expect(find.byKey(const Key('year_graduated_field')), findsNothing);
    expect(find.byKey(const Key('last_year_attended_field')), findsNothing);
  });

  testWidgets('former student fields follow the selected educational level',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    await _selectStudentStatus(tester, 'Former Student');
    expect(find.text('Last Educational Level Attended'), findsOneWidget);
    expect(find.byKey(const Key('program_field')), findsNothing);
    expect(find.byKey(const Key('last_year_attended_field')), findsNothing);

    await _selectEducationalLevel(tester, 'former_student', 'JHS');
    expect(find.byKey(const Key('last_year_attended_field')), findsOneWidget);
    expect(find.text('Last Grade Level Completed'), findsOneWidget);
    expect(find.byKey(const Key('program_field')), findsNothing);
    expect(
      find.byKey(const Key('last_year_level_completed_field')),
      findsNothing,
    );
    expect(find.byKey(const Key('year_graduated_field')), findsNothing);

    await _selectDropdown(
      tester,
      const ValueKey('last_grade_level_jhs'),
      'Grade 10',
    );
    await _selectEducationalLevel(tester, 'former_student', "Bachelor's");

    expect(find.byKey(const Key('program_field')), findsOneWidget);
    expect(find.byKey(const Key('last_year_attended_field')), findsOneWidget);
    expect(
      find.byKey(const Key('last_year_level_completed_field')),
      findsOneWidget,
    );
    expect(find.text('Last Grade Level Completed'), findsNothing);
    expect(find.byKey(const Key('year_graduated_field')), findsNothing);
  });

  testWidgets('alumni fields follow the selected educational level',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    await _selectStudentStatus(tester, 'Alumni');
    expect(find.text('Highest Educational Level Completed'), findsOneWidget);

    await _selectEducationalLevel(tester, 'alumni', 'SHS');
    expect(find.byKey(const Key('year_graduated_field')), findsOneWidget);
    expect(find.byKey(const Key('program_field')), findsNothing);
    expect(find.byKey(const Key('last_year_attended_field')), findsNothing);
    expect(find.text('Last Grade Level Completed'), findsNothing);

    await _selectEducationalLevel(tester, 'alumni', "Master's");
    expect(
      find.byKey(const Key('postgraduate_program_field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('year_graduated_field')), findsOneWidget);
    expect(find.byKey(const Key('last_year_attended_field')), findsNothing);
    expect(
      find.byKey(const Key('last_year_level_completed_field')),
      findsNothing,
    );
  });

  testWidgets('changing student status clears prior academic selections',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    await _selectStudentStatus(tester, 'Former Student');
    await _selectEducationalLevel(tester, 'former_student', 'SHS');
    await _selectDropdown(
      tester,
      const ValueKey('last_grade_level_shs'),
      'Grade 12',
    );

    await _selectStudentStatus(tester, 'Alumni');

    final levelField = tester.state<FormFieldState<String>>(
      find.byKey(const ValueKey('educational_level_alumni')),
    );
    expect(levelField.value, isNull);
    expect(find.byKey(const Key('year_graduated_field')), findsNothing);
    expect(find.text('Last Grade Level Completed'), findsNothing);
  });

  testWidgets('blank registration validates only fields currently displayed',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));

    final submit = find.byKey(const Key('create_account_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Select your student status to continue'), findsOneWidget);
    expect(find.text('Enter your first name'), findsOneWidget);
    expect(find.text('Enter your last name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Select your program'), findsNothing);
    expect(find.text('Enter your program'), findsNothing);
    expect(find.text('Enter a password'), findsOneWidget);
    expect(find.text('Confirm your password'), findsOneWidget);
    expect(
      find.text('Accept the Terms and Conditions to continue'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('former JHS validation does not require hidden program fields',
      (tester) async {
    await _pumpRegister(tester, const Size(412, 915));
    await _selectStudentStatus(tester, 'Former Student');
    await _selectEducationalLevel(tester, 'former_student', 'JHS');

    final submit = find.byKey(const Key('create_account_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Select your last year attended'), findsOneWidget);
    expect(
      find.text('Select your last completed grade level'),
      findsOneWidget,
    );
    expect(find.text('Select your program'), findsNothing);
    expect(find.text('Enter your program'), findsNothing);
  });

  testWidgets('registration submits only applicable alumni academic values',
      (tester) async {
    String? submittedProgram = 'not-called';
    String? submittedYearGraduated;
    String? submittedLastYearAttended = 'not-called';
    String? submittedLastGrade = 'not-called';
    String? submittedLastYearLevel = 'not-called';

    await _pumpRegister(
      tester,
      const Size(800, 1280),
      register: RegisterScreen(
        otpRequester: ({
          required String studentStatus,
          required String educationalLevel,
          required String firstName,
          required String lastName,
          required String email,
          required String password,
          String? program,
          String? yearGraduated,
          String? lastYearAttended,
          String? lastGradeLevelCompleted,
          String? lastYearLevelCompleted,
        }) async {
          expect(studentStatus, 'alumni');
          expect(educationalLevel, 'jhs');
          submittedProgram = program;
          submittedYearGraduated = yearGraduated;
          submittedLastYearAttended = lastYearAttended;
          submittedLastGrade = lastGradeLevelCompleted;
          submittedLastYearLevel = lastYearLevelCompleted;
          throw Exception('payload captured');
        },
      ),
    );

    await _selectStudentStatus(tester, 'Alumni');
    await _selectEducationalLevel(tester, 'alumni', 'JHS');
    await tester.enterText(find.byKey(const Key('first_name_field')), 'Anne');
    await tester.enterText(find.byKey(const Key('last_name_field')), 'Vane');
    await tester.enterText(
      find.byKey(const Key('registration_email_field')),
      'Anne@example.com',
    );
    await _selectDropdown(
      tester,
      const Key('year_graduated_field'),
      DateTime.now().year.toString(),
    );
    await tester.enterText(
      find.byKey(const Key('registration_password_field')),
      'SecurePass1!',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password_field')),
      'SecurePass1!',
    );
    await tester.tap(find.byKey(const Key('registration_terms_checkbox')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('create_account_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(submittedProgram, isNull);
    expect(submittedYearGraduated, DateTime.now().year.toString());
    expect(submittedLastYearAttended, isNull);
    expect(submittedLastGrade, isNull);
    expect(submittedLastYearLevel, isNull);
    expect(find.text('Could not create account'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('invalid email and weak password are explained inline',
      (tester) async {
    await _pumpRegister(tester, const Size(800, 1280));

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

  testWidgets('registration requests and verifies an OTP before success',
      (tester) async {
    var requestedEmail = '';
    var verifiedEmail = '';
    var verifiedOtp = '';
    var verifiedChallengeToken = '';

    await _pumpRegister(
      tester,
      const Size(800, 1280),
      register: RegisterScreen(
        otpRequester: ({
          required String studentStatus,
          required String educationalLevel,
          required String firstName,
          required String lastName,
          required String email,
          required String password,
          String? program,
          String? yearGraduated,
          String? lastYearAttended,
          String? lastGradeLevelCompleted,
          String? lastYearLevelCompleted,
        }) async {
          expect(studentStatus, 'alumni');
          expect(educationalLevel, 'bachelors');
          expect(firstName, 'Anne');
          expect(lastName, 'Vane');
          expect(password, 'SecurePass1!');
          expect(yearGraduated, DateTime.now().year.toString());
          expect(program, 'BSIT');
          expect(lastYearAttended, isNull);
          expect(lastGradeLevelCompleted, isNull);
          expect(lastYearLevelCompleted, isNull);
          requestedEmail = email;
          return OtpChallenge(
            challengeToken: 'registration-challenge',
            developmentOtp: '123456',
          );
        },
        otpVerifier: ({
          required String email,
          required String otp,
          required String challengeToken,
        }) async {
          verifiedEmail = email;
          verifiedOtp = otp;
          verifiedChallengeToken = challengeToken;
        },
      ),
    );

    await _selectStudentStatus(tester, 'Alumni');
    await _selectEducationalLevel(tester, 'alumni', "Bachelor's");
    await tester.enterText(find.byKey(const Key('first_name_field')), 'Anne');
    await tester.enterText(find.byKey(const Key('last_name_field')), 'Vane');
    await tester.enterText(
      find.byKey(const Key('registration_email_field')),
      'Anne@example.com',
    );
    await _selectDropdown(
      tester,
      const Key('year_graduated_field'),
      DateTime.now().year.toString(),
    );
    await _selectDropdown(tester, const Key('program_field'), 'BSIT');
    await tester.enterText(
      find.byKey(const Key('registration_password_field')),
      'SecurePass1!',
    );
    await tester.enterText(
      find.byKey(const Key('confirm_password_field')),
      'SecurePass1!',
    );
    await tester.tap(find.byKey(const Key('registration_terms_checkbox')));
    await tester.pump();

    final submit = find.byKey(const Key('create_account_button'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(requestedEmail, 'anne@example.com');
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Development code: 123456'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('registration_otp_field')),
      '123456',
    );
    await tester.tap(
      find.byKey(const Key('verify_registration_otp_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(verifiedEmail, 'anne@example.com');
    expect(verifiedOtp, '123456');
    expect(verifiedChallengeToken, 'registration-challenge');
    expect(find.text('Account created'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
