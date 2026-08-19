import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_project/constants.dart';
import 'package:capstone_project/models/profile_data.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_contract_adapter.dart';
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
  String? _currentUserId;
  DateTime? _accessTokenExpiresAt;
  final TokenStorage _storage = TokenStorage();
  Future<void>? _initialization;

  Uri _uri(String path) => ApiConstants.uri(path);

  bool get hasSession => _accessToken != null && _refreshToken != null;
  String? get accessToken => _accessToken;
  String? get currentUserId => _currentUserId;
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
    final storedUserId = await _storage.readUserId();

    final hasCompleteSession = accessToken?.trim().isNotEmpty == true &&
        refreshToken?.trim().isNotEmpty == true &&
        email?.trim().isNotEmpty == true;
    final hasAnySessionValue = accessToken != null ||
        refreshToken != null ||
        expiryMillis != null ||
        email != null ||
        storedUserId != null;

    if (!hasCompleteSession) {
      if (hasAnySessionValue) await _storage.clear();
      return;
    }

    _accessToken = accessToken!.trim();
    _refreshToken = refreshToken!.trim();
    _currentEmail = email!.trim();
    _currentUserId = storedUserId?.trim().isNotEmpty == true
        ? storedUserId!.trim()
        : _subjectFromAccessToken(_accessToken!);
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

  Future<_ApiResponse> _deleteJson(
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
      response =
          await http.delete(_uri(path), headers: headers).timeout(_timeout);
    } catch (error) {
      throw Exception(_friendlyNetworkMessage(error));
    }
    if (withAuth && response.statusCode == 401 && !retrying) {
      await _refreshOrThrow();
      return _deleteJson(path, withAuth: true, retrying: true);
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
      if (decoded is List) {
        return _ApiResponse(response.statusCode, {'items': decoded});
      }
    } catch (_) {}

    return _ApiResponse(response.statusCode, const {});
  }

  String _messageFor(Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) {
      if (message.trim().toLowerCase() == 'input validation failed') {
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          final detail = (errors.first as Map)['msg'];
          if (detail is String && detail.trim().isNotEmpty) {
            return detail.trim();
          }
        }
      }
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
    _currentUserId = null;
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
    String? currentUserId;
    final user = data['user'];
    if (user is Map) {
      final email = user['email'];
      if (email is String && email.trim().isNotEmpty) {
        currentEmail = email.trim();
      }
      final id = user['id'] ?? user['_id'];
      if (id != null && id.toString().trim().isNotEmpty) {
        currentUserId = id.toString().trim();
      }
    }

    if ((currentEmail == null || currentEmail.isEmpty) &&
        emailFallback?.trim().isNotEmpty == true) {
      currentEmail = emailFallback!.trim();
    }
    if (currentEmail == null || currentEmail.isEmpty) {
      throw Exception('Missing session email.');
    }
    currentUserId ??= _subjectFromAccessToken(accessToken);
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('Missing authenticated user ID.');
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
        userId: currentUserId,
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
    _currentUserId = currentUserId;
    _accessTokenExpiresAt = expiresAt;
  }

  String? _subjectFromAccessToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final subject = payload['sub'] ?? payload['id'];
      final value = subject?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
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

    if (response.statusCode == 404) {
      throw Exception(
        'Account registration is not available on the current server version. The backend must be updated before creating an account.',
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
    if (response.statusCode == 200) {
      final user = apiObject(response.data, key: 'user');
      if (user == null) throw Exception('Invalid profile response.');
      final normalized = normalizeProfileRecord(user);
      final email = normalized['email'];
      if (email is String && email.trim().isNotEmpty) {
        _currentEmail = email.trim();
      }
      final profile = ProfileData.fromJson(normalized);
      _acceptAuthenticatedProfile(profile);
      return profile;
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
    if (response.statusCode == 200) {
      final user = apiObject(response.data, key: 'user');
      if (user == null) throw Exception('Invalid profile response.');
      final normalized = normalizeProfileRecord(user);
      final email = normalized['email'];
      if (email is String && email.trim().isNotEmpty) {
        _currentEmail = email.trim();
      }
      final updated = ProfileData.fromJson(normalized);
      _acceptAuthenticatedProfile(updated);
      return updated;
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
    if (response.statusCode == 200) {
      if (response.data['accessToken'] != null &&
          response.data['refreshToken'] != null) {
        try {
          await _applySession(
            response.data,
            emailFallback: _currentEmail,
          );
        } catch (_) {
          await _clearSession();
          rethrow;
        }
      }
      return;
    }

    throw Exception(_messageFor(response.data, 'Failed to change password.'));
  }

  void _acceptAuthenticatedProfile(ProfileData profile) {
    final profileId = profile.id.trim();
    final sessionId = _currentUserId?.trim() ?? '';
    if (profileId.isEmpty) {
      throw Exception('Profile response is missing the authenticated user ID.');
    }
    if (sessionId.isNotEmpty && profileId != sessionId) {
      throw Exception(
          'Profile response does not match the authenticated account.');
    }
    _currentUserId = profileId;
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
    final receiptContentType = receiptImageContentType(bytes);
    if (receiptContentType == null) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'Please choose a valid JPG or PNG receipt image.',
      );
    }

    Future<_ApiResponse> sendRequest() async {
      final request = http.MultipartRequest('POST', _uri('/payments/receipt'));
      request.headers.addAll(authHeaders());
      request.fields['requestId'] = normalizedRequestId;
      final requestedPaymentType = paymentType.trim().toLowerCase();
      request.fields['paymentType'] =
          const {'onsite', 'gcash', 'receipt'}.contains(requestedPaymentType)
              ? requestedPaymentType
              : 'receipt';

      final safeName =
          fileName.trim().isEmpty ? 'receipt.jpg' : fileName.trim();
      request.files.add(
        http.MultipartFile.fromBytes(
          'receipt',
          bytes,
          filename: safeName,
          contentType: receiptContentType,
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
      return Map<String, dynamic>.from(decoded.data);
    }

    throw Exception(_messageFor(decoded.data, 'Failed to upload receipt.'));
  }

  Future<ProfileData> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileName,
  }) async {
    await _ensureValidSession();
    final imageContentType = receiptImageContentType(bytes);
    if (imageContentType == null) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        'Please choose a valid JPG or PNG profile image.',
      );
    }

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
          contentType: imageContentType,
        ),
      );

      return _sendMultipart(request);
    }

    var decoded = await sendRequest();
    if (decoded.statusCode == 401) {
      await _refreshOrThrow();
      decoded = await sendRequest();
    }

    if ((decoded.statusCode == 200 || decoded.statusCode == 201) &&
        decoded.data['success'] == true) {
      final rawProfile = apiObject(decoded.data, key: 'profile');
      if (rawProfile == null) throw Exception('Invalid upload response.');
      final profile = ProfileData.fromJson(normalizeProfileRecord(rawProfile));
      _acceptAuthenticatedProfile(profile);
      return profile;
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
        'documentType': docName.trim(),
        'purpose': purpose.trim(),
      },
      withAuth: true,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (response.data['persisted'] == false) {
        throw Exception(
          'The backend is using temporary storage. Configure MongoDB before submitting requests.',
        );
      }
      final request = apiObject(response.data, key: 'request');
      if (request == null) throw Exception('Invalid request response.');
      final normalized = normalizeRequestRecord(request);
      final requestId = [
        normalized['requestId'],
        normalized['id'],
        normalized['_id'],
      ]
          .map((value) => value?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (requestId.isEmpty) {
        throw Exception(
          'The server did not return a database ID for this request.',
        );
      }
      return {
        'success': true,
        'persisted': response.data['persisted'] != false,
        'request': normalized,
      };
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
    if (response.statusCode == 200) {
      final records = apiList(response.data, key: 'requests')
          .map(normalizeRequestRecord)
          .toList();
      if (filtered.isEmpty) return records;
      final accepted = filtered.map((value) => value.toLowerCase()).toSet();
      return records.where((item) {
        final status = item['status']?.toString().trim().toLowerCase() ?? '';
        return accepted.contains(status);
      }).toList();
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
    if (response.statusCode == 200) {
      return apiList(response.data, key: 'notifications')
          .map(normalizeNotificationRecord)
          .take(safeLimit)
          .toList();
    }

    throw Exception(
        _messageFor(response.data, 'Failed to load notifications.'));
  }

  Future<void> markNotificationRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        notificationId,
        'notificationId',
        'A notification ID is required.',
      );
    }
    final response = await _putJson(
      '/notifications/${Uri.encodeComponent(id)}/read',
      const {},
      withAuth: true,
    );
    if (response.statusCode != 200) {
      throw Exception(
        _messageFor(response.data, 'Failed to mark notification as read.'),
      );
    }
  }

  Future<void> markAllNotificationsRead() async {
    final response = await _putJson(
      '/notifications/mark-all-read',
      const {},
      withAuth: true,
    );
    if (response.statusCode != 200) {
      throw Exception(
        _messageFor(response.data, 'Failed to mark notifications as read.'),
      );
    }
  }

  Future<void> dismissNotification(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        notificationId,
        'notificationId',
        'A notification ID is required.',
      );
    }
    final response = await _deleteJson(
      '/notifications/${Uri.encodeComponent(id)}',
      withAuth: true,
    );
    if (response.statusCode != 200) {
      throw Exception(
        _messageFor(response.data, 'Failed to dismiss notification.'),
      );
    }
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
    if (response.statusCode == 200) {
      return apiList(response.data, key: 'transactions')
          .map(normalizeTransactionRecord)
          .take(safeLimit)
          .toList();
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
        if (bankName?.trim().isNotEmpty == true) 'bankName': bankName!.trim(),
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
      withAuth: true,
    );

    if (response.statusCode == 201 && response.data['success'] == true) {
      final refund = apiObject(response.data, key: 'refund');
      return {
        ...response.data,
        'refundStatus':
            refund?['status']?.toString().toLowerCase() ?? 'pending',
      };
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
      final otp = response.data['otp'];
      final challengeToken = response.data['challengeToken']?.toString() ?? '';
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

MediaType? receiptImageContentType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return MediaType('image', 'png');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return MediaType('image', 'jpeg');
  }
  return null;
}

class _ApiResponse {
  _ApiResponse(this.statusCode, this.data);

  final int statusCode;
  final Map<String, dynamic> data;
}
