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

  bool get isPastStudent {
    final normalized = role.trim().toLowerCase();
    return normalized == 'alumni' || normalized == 'former_student';
  }

  String get roleLabel {
    switch (role.trim().toLowerCase()) {
      case 'former_student':
        return 'Former student';
      case 'alumni':
        return 'Alumni';
      case 'student':
        return 'Current student';
      default:
        return role.trim();
    }
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
      'studentId': studentId.trim(),
      'yearLevel': yearLevel.trim(),
      'program': program.trim(),
      'schoolEmail': schoolEmail.trim(),
      'personalEmail': personalEmail.trim(),
    };
    if (profileImageUrl.trim().isNotEmpty) {
      data['profileImageUrl'] = profileImageUrl.trim();
    }
    return data;
  }
}
