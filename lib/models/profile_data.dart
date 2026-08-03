class ProfileData {
  const ProfileData({
    required this.firstName,
    required this.lastName,
    required this.studentId,
    required this.yearLevel,
    required this.program,
    required this.schoolEmail,
    required this.personalEmail,
    required this.role,
    this.profileImageUrl = '',
  });

  final String firstName;
  final String lastName;
  final String studentId;
  final String yearLevel;
  final String program;
  final String schoolEmail;
  final String personalEmail;
  final String role;
  final String profileImageUrl;

  String get normalizedRole =>
      role.trim().toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');

  bool get isCurrentStudent {
    return const {'student', 'current_student'}.contains(normalizedRole);
  }

  bool get isFormerStudent {
    return const {
      'former_student',
      'stopped_student',
      'student_stopped',
      'stopped',
    }.contains(normalizedRole);
  }

  bool get isAlumni => normalizedRole == 'alumni';

  bool get isMasters {
    return const {
      'masters',
      'master',
      "master's",
      'masters_student',
      'graduate_student',
    }.contains(normalizedRole);
  }

  bool get isDoctorate {
    return const {
      'doctorate',
      'doctoral',
      'doctorate_student',
      'doctoral_student',
      'phd',
    }.contains(normalizedRole);
  }

  bool get isPastStudent {
    return isFormerStudent || isAlumni || isMasters || isDoctorate;
  }

  bool get usesSchoolLogin => isCurrentStudent;

  String get academicYearLabel {
    if (isCurrentStudent) return 'Year level';
    if (isFormerStudent) return 'Year last attended';
    if (isAlumni) return 'Year graduated';
    if (isMasters || isDoctorate) {
      return 'Year graduated / last attended';
    }
    return 'Academic year';
  }

  String get academicYearHint {
    return isCurrentStudent ? 'e.g. 4th Year' : 'e.g. 2025';
  }

  String get programLabel {
    if (isFormerStudent) return 'Program attended';
    if (isMasters) return "Master's program";
    if (isDoctorate) return 'Doctorate program';
    return 'Program';
  }

  String get programHint {
    if (isMasters) return 'e.g. Master of Information Technology';
    if (isDoctorate) return 'e.g. Doctor of Information Technology';
    return 'e.g. BS Information Technology';
  }

  String get roleLabel {
    if (isCurrentStudent) return 'Current student';
    if (isFormerStudent) return 'Former / stopped student';
    if (isAlumni) return 'Alumni';
    if (isMasters) return "Master's";
    if (isDoctorate) return 'Doctorate';
    return role.trim().isEmpty ? 'Requester' : role.trim();
  }

  String get fullName {
    final combined = '${firstName.trim()} ${lastName.trim()}'.trim();
    return combined.isEmpty ? 'Unknown' : combined;
  }

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      if (value is String) return value.trim();
      return '';
    }

    final personalEmail = readString('personalEmail');
    final email = readString('email');
    final role = readString('role');
    final profileImageUrl = readString('profileImageUrl');
    final profilePic = readString('profilePic');

    return ProfileData(
      firstName: readString('firstName'),
      lastName: readString('lastName'),
      studentId: readString('studentId'),
      yearLevel: readString('yearLevel'),
      program: readString('program'),
      schoolEmail: readString('schoolEmail'),
      personalEmail: personalEmail.isNotEmpty ? personalEmail : email,
      role: role.isNotEmpty ? role : 'alumni',
      profileImageUrl:
          profileImageUrl.isNotEmpty ? profileImageUrl : profilePic,
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'studentId': isCurrentStudent ? studentId.trim() : '',
      'yearLevel': yearLevel.trim(),
      'program': program.trim(),
      'schoolEmail': usesSchoolLogin ? schoolEmail.trim() : '',
      'personalEmail': usesSchoolLogin ? '' : personalEmail.trim(),
    };
    if (profileImageUrl.trim().isNotEmpty) {
      data['profileImageUrl'] = profileImageUrl.trim();
    }
    return data;
  }
}
