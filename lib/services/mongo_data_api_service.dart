import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_project/constants.dart';
import 'package:capstone_project/models/profile_data.dart';
import 'package:http/http.dart' as http;
import 'token_storage.dart';

class OtpChallenge {
  OtpChallenge({
    required String challengeToken,
    String? developmentOtp,
  })  : challengeToken = challengeToken.trim(),
        developmentOtp = developmentOtp?.trim() {
    if (this.challengeToken.isEmpty) {
      throw ArgumentError.value(
        challengeToken,
        'challengeToken',
        'An OTP challenge token is required.',
      );
    }
  }

  final String challengeToken;
  final String? developmentOtp;
}

class MongoDataApiService {
  MongoDataApiService._();

  static final MongoDataApiService instance = MongoDataApiService._();
  // OTP requests can include a 5-second mailbox check followed by SMTP
  // delivery, whose socket timeout is 15 seconds.
  static const Duration _timeout = Duration(seconds: 30);

  String? _accessToken;
  String? _refreshToken;
  String? _currentEmail;
  DateTime? _accessTokenExpiresAt;
  final TokenStorage _storage = TokenStorage();
  Future<void>? _initialization;

  Uri _uri(String path) => ApiConstants.uri(path);

  bool get hasSession => _accessToken != null && _refreshToken != null;
  String? get accessToken => _accessToken;
  DateTime? get accessTokenExpiresAt => _accessTokenExpiresAt;

  Map<String, String> authHeaders() {
    if (_accessToken == null) return const {};
    return {'Authorization': 'Bearer $_accessToken'};
  }

  Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _loadStoredSession();
    _initialization = initialization;
    return initialization;
  }

  Future<void> _loadStoredSession() async {
    final accessToken = await _storage.readAccessToken();
    final refreshToken = await _storage.readRefreshToken();
    final expiryMillis = await _storage.readExpiryMillis();
    final email = await _storage.readEmail();

    final hasCompleteSession = accessToken?.trim().isNotEmpty == true &&
        refreshToken?.trim().isNotEmpty == true &&
        email?.trim().isNotEmpty == true;
    final hasAnySessionValue = accessToken != null ||
        refreshToken != null ||
        expiryMillis != null ||
        email != null;

    if (!hasCompleteSession) {
      if (hasAnySessionValue) await _storage.clear();
      return;
    }

    _accessToken = accessToken!.trim();
    _refreshToken = refreshToken!.trim();
    _currentEmail = email!.trim();
    if (expiryMillis != null) {
      _accessTokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(expiryMillis);
    }
  }

  Future<_ApiResponse> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool withAuth = false,
    bool retrying = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (withAuth) {
      await _ensureValidSession();
      headers.addAll(authHeaders());
    }

    late final http.Response response;
    try {
      response = await http
          .post(
            _uri(path),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (error) {
      throw Exception(_friendlyNetworkMessage(error));
    }

    if (withAuth && response.statusCode == 401 && !retrying) {
      await _refreshOrThrow();
      return _postJson(path, body, withAuth: true, retrying: true);
    }

    return _decodeResponse(response);
  }

  Future<_ApiResponse> _getJson(
    String path, {
    bool withAuth = false,
    bool retrying = false,
  }) async {
    final headers = <String, String>{};
    if (withAuth) {
      await _ensureValidSession();
      headers.addAll(authHeaders());
    }

    late final http.Response response;
    try {
      response = await http.get(_uri(path), headers: headers).timeout(_timeout);
    } catch (error) {
      throw Exception(_friendlyNetworkMessage(error));
    }
    if (withAuth && response.statusCode == 401 && !retrying) {
      await _refreshOrThrow();
      return _getJson(path, withAuth: true, retrying: true);
    }

    return _decodeResponse(response);
  }

  Future<_ApiResponse> _putJson(
    String path,
    Map<String, dynamic> body, {
    bool withAuth = false,
    bool retrying = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (withAuth) {
      await _ensureValidSession();
      headers.addAll(authHeaders());
    }

    late final http.Response response;
    try {
      response = await http
          .put(
            _uri(path),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (error) {
      throw Exception(_friendlyNetworkMessage(error));
    }
    if (withAuth && response.statusCode == 401 && !retrying) {
      await _refreshOrThrow();
      return _putJson(path, body, withAuth: true, retrying: true);
    }

    return _decodeResponse(response);
  }

  Future<_ApiResponse> _sendMultipart(http.MultipartRequest request) async {
    late final http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(_timeout);
    } catch (error) {
      throw Exception(_friendlyNetworkMessage(error));
    }
    final response = await http.Response.fromStream(streamed);
    return _decodeResponse(response);
  }

  _ApiResponse _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      return _ApiResponse(response.statusCode, const {});
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return _ApiResponse(response.statusCode, decoded);
      }
    } catch (_) {}

    return _ApiResponse(response.statusCode, const {});
  }

  String _messageFor(Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
    return fallback;
  }

  String _friendlyNetworkMessage(Object error) {
    if (error is SocketException) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (error is TimeoutException) {
      return 'The request timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _discardSessionInMemory() {
    _accessToken = null;
    _refreshToken = null;
    _currentEmail = null;
    _accessTokenExpiresAt = null;
  }

  Future<void> _clearSession() async {
    _discardSessionInMemory();
    await _storage.clear();
  }

  Future<void> _applySession(
    Map<String, dynamic> data, {
    String? emailFallback,
  }) async {
    final accessToken = data['accessToken']?.toString().trim() ?? '';
    final refreshToken = data['refreshToken']?.toString().trim() ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw Exception('Missing session tokens.');
    }

    String? currentEmail;
    final user = data['user'];
    if (user is Map) {
      final email = user['email'];
      if (email is String && email.trim().isNotEmpty) {
        currentEmail = email.trim();
      }
    }

    if ((currentEmail == null || currentEmail.isEmpty) &&
        emailFallback?.trim().isNotEmpty == true) {
      currentEmail = emailFallback!.trim();
    }
    if (currentEmail == null || currentEmail.isEmpty) {
      throw Exception('Missing session email.');
    }

    DateTime? expiresAt;
    final expiresIn = data['expiresInSeconds'];
    if (expiresIn is num) {
      expiresAt = DateTime.now().add(Duration(seconds: expiresIn.toInt()));
    }

    try {
      await _storage.writeSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiryMillis: expiresAt?.millisecondsSinceEpoch,
        email: currentEmail,
      );
    } catch (_) {
      _discardSessionInMemory();
      try {
        await _storage.clear();
      } catch (_) {
        // Preserve the original secure-storage error.
      }
      rethrow;
    }

    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _currentEmail = currentEmail;
    _accessTokenExpiresAt = expiresAt;
  }

  Future<void> _refreshOrThrow() async {
    try {
      await refreshSession();
    } catch (_) {
      await _clearSession();
      throw Exception('Session expired. Please log in again.');
    }
  }

  Future<void> _ensureValidSession() async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    if (_accessTokenExpiresAt != null) {
      final refreshAt =
          _accessTokenExpiresAt!.subtract(const Duration(seconds: 30));
      if (DateTime.now().isAfter(refreshAt)) {
        await _refreshOrThrow();
      }
    }
  }

  Future<OtpChallenge> requestRegisterOtp({
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
    final body = <String, dynamic>{
      'studentStatus': studentStatus.trim(),
      'educationalLevel': educationalLevel.trim(),
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'password': password.trim(),
    };
    if (program?.trim().isNotEmpty == true) {
      body['program'] = program!.trim();
    }
    if (yearGraduated?.trim().isNotEmpty == true) {
      body['yearGraduated'] = yearGraduated!.trim();
    }
    if (lastYearAttended?.trim().isNotEmpty == true) {
      body['lastYearAttended'] = lastYearAttended!.trim();
    }
    if (lastGradeLevelCompleted?.trim().isNotEmpty == true) {
      body['lastGradeLevelCompleted'] = lastGradeLevelCompleted!.trim();
    }
    if (lastYearLevelCompleted?.trim().isNotEmpty == true) {
      body['lastYearLevelCompleted'] = lastYearLevelCompleted!.trim();
    }

    final response = await _postJson('/auth/register/request-otp', body);

    if (response.statusCode == 200 && response.data['success'] == true) {
      final challengeToken = response.data['challengeToken'];
      if (challengeToken is! String || challengeToken.trim().isEmpty) {
        throw Exception('Missing OTP challenge token.');
      }
      final otp = response.data['otp'];
      return OtpChallenge(
        challengeToken: challengeToken,
        developmentOtp: otp?.toString(),
      );
    }

    throw Exception(_messageFor(response.data, 'Failed to request OTP.'));
  }

  Future<void> verifyRegisterOtp({
    required String email,
    required String otp,
    required String challengeToken,
  }) async {
    final normalizedChallengeToken = challengeToken.trim();
    if (normalizedChallengeToken.isEmpty) {
      throw ArgumentError.value(
        challengeToken,
        'challengeToken',
        'An OTP challenge token is required.',
      );
    }
    final response = await _postJson('/auth/register/verify-otp', {
      'email': email.trim(),
      'otp': otp.trim(),
      'challengeToken': normalizedChallengeToken,
    });

    if ((response.statusCode == 200 || response.statusCode == 201) &&
        response.data['success'] == true) {
      return;
    }

    throw Exception(_messageFor(response.data, 'OTP verification failed.'));
  }

  Future<ProfileData> fetchProfile() async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _getJson('/profile', withAuth: true);
    if (response.statusCode == 200 && response.data['success'] == true) {
      final user = response.data['user'];
      if (user is Map<String, dynamic>) {
        final email = user['email'];
        if (email is String && email.trim().isNotEmpty) {
          _currentEmail = email.trim();
        }
        return ProfileData.fromJson(user);
      }
      throw Exception('Invalid profile response.');
    }

    throw Exception(_messageFor(response.data, 'Failed to load profile.'));
  }

  Future<ProfileData> updateProfile({
    required ProfileData profile,
  }) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _putJson(
      '/profile',
      profile.toJson(),
      withAuth: true,
    );
    if (response.statusCode == 200 && response.data['success'] == true) {
      final user = response.data['user'];
      if (user is Map<String, dynamic>) {
        final email = user['email'];
        if (email is String && email.trim().isNotEmpty) {
          _currentEmail = email.trim();
        }
        return ProfileData.fromJson(user);
      }
      throw Exception('Invalid profile response.');
    }

    throw Exception(_messageFor(response.data, 'Failed to update profile.'));
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }
    if (currentPassword.isEmpty) {
      throw ArgumentError.value(
        currentPassword,
        'currentPassword',
        'Current password is required.',
      );
    }

    final response = await _putJson(
      '/profile/password',
      {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      withAuth: true,
    );
    if (response.statusCode == 200 && response.data['success'] == true) {
      try {
        await _applySession(
          response.data,
          emailFallback: _currentEmail,
        );
      } catch (_) {
        await _clearSession();
        rethrow;
      }
      return;
    }

    throw Exception(_messageFor(response.data, 'Failed to change password.'));
  }

  Future<bool> login({
    required String email,
    required String password,
    String? role,
  }) async {
    await _clearSession();
    final body = {
      'email': email.trim().toLowerCase(),
      'password': password,
    };
    if (role != null && role.trim().isNotEmpty) {
      body['role'] = role.trim();
    }
    final response = await _postJson('/auth/login', body);

    if (response.statusCode == 200 && response.data['success'] == true) {
      await _applySession(response.data, emailFallback: email);
      return true;
    }

    // Preserve the centralized API's reason, including inactive or
    // deactivated-account responses, so the login screen can show it.
    throw Exception(_messageFor(response.data, 'Login failed.'));
  }

  Future<void> refreshSession() async {
    final email = _currentEmail;
    final refreshToken = _refreshToken;

    if ((email?.isEmpty ?? true) || refreshToken == null) {
      throw Exception('No refresh session available.');
    }

    final response = await _postJson('/auth/refresh', {
      'email': email,
      'refreshToken': refreshToken,
    });

    if (response.statusCode == 200 && response.data['success'] == true) {
      await _applySession(response.data, emailFallback: email);
      return;
    }

    throw Exception(_messageFor(response.data, 'Session refresh failed.'));
  }

  Future<void> logout() async {
    final email = _currentEmail;
    final refreshToken = _refreshToken;
    await _clearSession();

    if (email == null || refreshToken == null) {
      return;
    }

    try {
      await _postJson('/auth/logout', {
        'email': email,
        'refreshToken': refreshToken,
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>> uploadReceipt({
    required Uint8List bytes,
    required String fileName,
    required String requestId,
    required String paymentType,
    required String docName,
    required String purpose,
  }) async {
    await _ensureValidSession();
    final normalizedRequestId = requestId.trim();
    if (normalizedRequestId.isEmpty) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'A request ID is required to upload a receipt.',
      );
    }

    Future<_ApiResponse> sendRequest() async {
      final request = http.MultipartRequest('POST', _uri('/payments/receipt'));
      request.headers.addAll(authHeaders());
      request.fields['requestId'] = normalizedRequestId;
      request.fields['paymentType'] = paymentType;
      request.fields['docName'] = docName;
      request.fields['purpose'] = purpose;

      final safeName =
          fileName.trim().isEmpty ? 'receipt.jpg' : fileName.trim();
      request.files.add(
        http.MultipartFile.fromBytes(
          'receipt',
          bytes,
          filename: safeName,
        ),
      );

      return _sendMultipart(request);
    }

    var decoded = await sendRequest();
    if (decoded.statusCode == 401) {
      await _refreshOrThrow();
      decoded = await sendRequest();
    }

    if (decoded.statusCode == 201 && decoded.data['success'] == true) {
      return decoded.data;
    }

    throw Exception(_messageFor(decoded.data, 'Failed to upload receipt.'));
  }

  Future<ProfileData> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileName,
  }) async {
    await _ensureValidSession();

    Future<_ApiResponse> sendRequest() async {
      final request = http.MultipartRequest('POST', _uri('/profile/photo'));
      request.headers.addAll(authHeaders());

      final safeName =
          fileName.trim().isEmpty ? 'profile.jpg' : fileName.trim();
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: safeName,
        ),
      );

      return _sendMultipart(request);
    }

    var decoded = await sendRequest();
    if (decoded.statusCode == 401) {
      await _refreshOrThrow();
      decoded = await sendRequest();
    }

    if (decoded.statusCode == 201 && decoded.data['success'] == true) {
      final user = decoded.data['profile'];
      if (user is Map<String, dynamic>) {
        final email = user['email'];
        if (email is String && email.trim().isNotEmpty) {
          _currentEmail = email.trim();
        }
        return ProfileData.fromJson(user);
      }
      throw Exception('Invalid profile response.');
    }

    throw Exception(_messageFor(decoded.data, 'Failed to upload photo.'));
  }

  Future<Map<String, dynamic>> createDocumentRequest({
    required String docName,
    required String purpose,
  }) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _postJson(
      '/requests',
      {
        'docName': docName.trim(),
        'purpose': purpose.trim(),
      },
      withAuth: true,
    );

    if (response.statusCode == 201 && response.data['success'] == true) {
      return response.data;
    }

    throw Exception(_messageFor(response.data, 'Failed to submit request.'));
  }

  Future<List<Map<String, dynamic>>> fetchRequests({
    List<String>? statuses,
  }) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final filtered = (statuses ?? [])
        .map((status) => status.trim())
        .where((status) => status.isNotEmpty)
        .toList();

    final path = filtered.isEmpty
        ? '/requests'
        : '/requests?status=${Uri.encodeQueryComponent(filtered.join(','))}';

    final response = await _getJson(path, withAuth: true);
    if (response.statusCode == 200 && response.data['success'] == true) {
      final raw = response.data['requests'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    }

    throw Exception(_messageFor(response.data, 'Failed to load requests.'));
  }

  Future<Map<String, dynamic>?> fetchReceiptForRequest({
    required String docName,
    required String purpose,
  }) async {
    final query =
        'docName=${Uri.encodeQueryComponent(docName.trim())}&purpose=${Uri.encodeQueryComponent(purpose.trim())}';
    final response = await _getJson('/receipts?$query', withAuth: true);
    if (response.statusCode == 200 && response.data['success'] == true) {
      final receipt = response.data['receipt'];
      if (receipt is Map) {
        return Map<String, dynamic>.from(receipt);
      }
      return null;
    }

    throw Exception(_messageFor(response.data, 'Failed to load receipt.'));
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(
      {int limit = 50}) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final safeLimit = limit <= 0 ? 50 : limit;
    final response = await _getJson(
      '/notifications?limit=$safeLimit',
      withAuth: true,
    );
    if (response.statusCode == 200 && response.data['success'] == true) {
      final raw = response.data['notifications'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    }

    throw Exception(
        _messageFor(response.data, 'Failed to load notifications.'));
  }

  Future<List<Map<String, dynamic>>> fetchTransactions({int limit = 50}) async {
    if (_accessToken == null) {
      throw Exception('Not authenticated.');
    }

    final safeLimit = limit <= 0 ? 50 : limit;
    final response = await _getJson(
      '/transactions?limit=$safeLimit',
      withAuth: true,
    );
    if (response.statusCode == 200 && response.data['success'] == true) {
      final raw = response.data['transactions'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      return [];
    }

    throw Exception(_messageFor(response.data, 'Failed to load transactions.'));
  }

  Future<Map<String, dynamic>> requestRefund({
    required String transactionId,
    required String refundMethod,
    required String accountName,
    required String accountNumber,
    String? bankName,
    String? reason,
  }) async {
    final response = await _postJson(
      '/refunds',
      {
        'transactionId': transactionId.trim(),
        'refundMethod': refundMethod.trim(),
        'accountName': accountName.trim(),
        'accountNumber': accountNumber.trim(),
        if (bankName != null) 'bankName': bankName.trim(),
        if (reason != null) 'reason': reason.trim(),
      },
      withAuth: true,
    );

    if (response.statusCode == 201 && response.data['success'] == true) {
      return response.data;
    }

    // Treat an already-recorded refund as an idempotent success. This can
    // happen when the first submission succeeded but its response was lost.
    if (response.statusCode == 409 &&
        response.data['refundStatus']?.toString().trim().isNotEmpty == true) {
      return {
        ...response.data,
        // Older API deployments may not return this explicit marker yet.
        'alreadyRequested': true,
      };
    }

    throw Exception(
      _messageFor(response.data, 'Failed to submit refund request.'),
    );
  }

  Future<OtpChallenge> requestPasswordResetOtp({required String email}) async {
    final response = await _postJson('/auth/forgot-password/request-otp', {
      'email': email.trim(),
    });

    if (response.statusCode == 200 && response.data['success'] == true) {
      final challengeToken = response.data['challengeToken'];
      if (challengeToken is! String || challengeToken.trim().isEmpty) {
        throw Exception('Missing OTP challenge token.');
      }
      final otp = response.data['otp'];
      return OtpChallenge(
        challengeToken: challengeToken,
        developmentOtp: otp?.toString(),
      );
    }

    throw Exception(
      _messageFor(response.data, 'Failed to request password reset OTP.'),
    );
  }

  Future<String> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String challengeToken,
  }) async {
    final normalizedChallengeToken = challengeToken.trim();
    if (normalizedChallengeToken.isEmpty) {
      throw ArgumentError.value(
        challengeToken,
        'challengeToken',
        'An OTP challenge token is required.',
      );
    }
    final response = await _postJson('/auth/forgot-password/verify-otp', {
      'email': email.trim(),
      'otp': otp.trim(),
      'challengeToken': normalizedChallengeToken,
    });

    if (response.statusCode == 200 && response.data['success'] == true) {
      final resetToken = response.data['resetToken'];
      if (resetToken is String && resetToken.trim().isNotEmpty) {
        return resetToken;
      }
      throw Exception('Missing reset token.');
    }

    throw Exception(_messageFor(response.data, 'OTP verification failed.'));
  }

  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await _postJson('/auth/forgot-password/reset', {
      'resetToken': resetToken.trim(),
      'newPassword': newPassword,
    });

    if (response.statusCode == 200 && response.data['success'] == true) {
      return;
    }

    throw Exception(_messageFor(response.data, 'Password reset failed.'));
  }
}

class _ApiResponse {
  _ApiResponse(this.statusCode, this.data);

  final int statusCode;
  final Map<String, dynamic> data;
}
