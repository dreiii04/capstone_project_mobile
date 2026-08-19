import 'package:capstone_project/models/profile_data.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileData _profileWithRole(String role) => ProfileData(
      firstName: 'Test',
      lastName: 'Requester',
      studentId: '',
      yearLevel: '2025',
      program: 'Information Technology',
      schoolEmail: '',
      personalEmail: 'requester@example.com',
      role: role,
    );

void main() {
  test('requester roles use friendly, stable labels', () {
    expect(_profileWithRole('former_student').roleLabel,
        'Former / stopped student');
    expect(_profileWithRole('masters').roleLabel, "Master's");
    expect(_profileWithRole('doctorate').roleLabel, 'Doctorate');
    expect(_profileWithRole('Student').roleLabel, 'Current student');
    expect(_profileWithRole("Master's").roleLabel, "Master's");
    expect(_profileWithRole('phd').roleLabel, 'Doctorate');
  });

  test('postgraduate and former requester profiles use requester fields', () {
    for (final role in [
      'former_student',
      'former-student',
      'alumni',
      'masters',
      'doctorate',
    ]) {
      expect(
        _profileWithRole(role).isPastStudent,
        isTrue,
        reason: '$role should not require current-student-only fields',
      );
    }

    expect(_profileWithRole('student').isPastStudent, isFalse);
  });

  test('personal information labels depend on requester type', () {
    final student = _profileWithRole('student');
    expect(student.academicYearLabel, 'Year level');
    expect(student.programLabel, 'Program');
    expect(student.usesSchoolLogin, isTrue);

    final former = _profileWithRole('former_student');
    expect(former.academicYearLabel, 'Year last attended');
    expect(former.programLabel, 'Program attended');
    expect(former.usesSchoolLogin, isFalse);

    final alumni = _profileWithRole('alumni');
    expect(alumni.academicYearLabel, 'Year graduated');
    expect(alumni.programLabel, 'Program');

    final masters = _profileWithRole('masters');
    expect(masters.academicYearLabel, 'Year graduated / last attended');
    expect(masters.programLabel, "Master's program");

    final doctorate = _profileWithRole('doctorate');
    expect(doctorate.academicYearLabel, 'Year graduated / last attended');
    expect(doctorate.programLabel, 'Doctorate program');
  });

  test('profile updates only send fields used by the account type', () {
    final studentJson = const ProfileData(
      firstName: 'Current',
      lastName: 'Student',
      studentId: '2026-00001',
      yearLevel: '4th Year',
      program: 'Information Technology',
      schoolEmail: 'student@school.edu',
      personalEmail: 'duplicate@example.com',
      role: 'student',
    ).toJson();
    expect(studentJson['schoolEmail'], 'student@school.edu');
    expect(studentJson['personalEmail'], isEmpty);

    final alumniJson = _profileWithRole('alumni').toJson();
    expect(alumniJson['studentId'], isEmpty);
    expect(alumniJson['schoolEmail'], isEmpty);
    expect(alumniJson['personalEmail'], 'requester@example.com');
  });

  test('profile keeps the permanent database ID out of editable payloads', () {
    final profile = ProfileData.fromJson(const {
      '_id': '507f1f77bcf86cd799439011',
      'firstName': 'Renamed',
      'lastName': 'Account',
      'email': 'requester@example.com',
      'role': 'alumni',
    });

    expect(profile.id, '507f1f77bcf86cd799439011');
    expect(profile.toJson().containsKey('id'), isFalse);
    expect(profile.toJson().containsKey('_id'), isFalse);
  });
}
