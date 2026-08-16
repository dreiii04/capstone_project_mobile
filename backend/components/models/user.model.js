export function normalizeRole(role) {
  const normalized = String(role || '')
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
  if (normalized === 'student') return 'student';
  if (new Set([
    'former_student',
    'stopped_student',
    'student_stopped',
    'stopped',
  ]).has(normalized)) {
    return 'former_student';
  }
  if (new Set([
    'masters',
    'master',
    "master's",
    'masters_student',
    'graduate_student',
  ]).has(normalized)) {
    return 'masters';
  }
  if (new Set([
    'doctorate',
    'doctoral',
    'doctorate_student',
    'doctoral_student',
    'phd',
  ]).has(normalized)) {
    return 'doctorate';
  }
  return 'alumni';
}

export function requesterRoleLabel(role) {
  switch (normalizeRole(role)) {
    case 'student':
      return 'Student';
    case 'former_student':
      return 'Former Student';
    case 'masters':
      return "Master's";
    case 'doctorate':
      return 'Doctorate';
    default:
      return 'Alumni';
  }
}

export function parseRegistrationRole(role) {
  const normalized = String(role || '')
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
  const accepted = new Set([
    'former_student',
    'stopped_student',
    'student_stopped',
    'stopped',
    'alumni',
    'masters',
    'master',
    "master's",
    'masters_student',
    'graduate_student',
    'doctorate',
    'doctoral',
    'doctorate_student',
    'doctoral_student',
    'phd',
  ]);
  return accepted.has(normalized) ? normalizeRole(normalized) : '';
}

export function buildUserResponse(user) {
  if (!user) return null;
  const role = normalizeRole(user.role);
  return {
    id: user._id || user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    role,
    roleLabel: requesterRoleLabel(role),
  };
}

export function buildProfileResponse(user) {
  if (!user) return null;
  const role = normalizeRole(user.role);
  const isStudent = role === 'student';
  const schoolEmail = isStudent ? user.schoolEmail || '' : '';
  return {
    id: user._id || user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    profileImageUrl: user.profileImageUrl || user.profilePic || '',
    email: isStudent && schoolEmail ? schoolEmail : user.email,
    personalEmail: isStudent ? '' : user.personalEmail || user.email || '',
    role: role || 'alumni',
    roleLabel: requesterRoleLabel(role),
    schoolEmail,
    studentId: isStudent ? user.studentId || '' : '',
    studentStatus: user.studentStatus || role,
    educationalLevel: user.educationalLevel || '',
    yearLevel: user.yearLevel || '',
    program: user.program || '',
    yearGraduated: user.yearGraduated || '',
    lastYearAttended: user.lastYearAttended || '',
    lastGradeLevelCompleted: user.lastGradeLevelCompleted || '',
    lastYearLevelCompleted: user.lastYearLevelCompleted || '',
  };
}
