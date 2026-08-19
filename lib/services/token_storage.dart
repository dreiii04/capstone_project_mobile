import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  static const _keyAccess = 'accessToken';
  static const _keyRefresh = 'refreshToken';
  static const _keyExpiry = 'accessExpiryMillis';
  static const _keyEmail = 'currentEmail';
  static const _keyUserId = 'currentUserId';

  Future<void> writeAccessToken(String token) async {
    await _secure.write(key: _keyAccess, value: token);
  }

  Future<void> writeRefreshToken(String token) async {
    await _secure.write(key: _keyRefresh, value: token);
  }

  Future<void> writeExpiryMillis(int millis) async {
    await _secure.write(key: _keyExpiry, value: millis.toString());
  }

  Future<void> writeEmail(String email) async {
    await _secure.write(key: _keyEmail, value: email);
  }

  Future<void> writeUserId(String userId) async {
    await _secure.write(key: _keyUserId, value: userId);
  }

  Future<void> writeSession({
    required String accessToken,
    required String refreshToken,
    required int? expiryMillis,
    required String email,
    required String userId,
  }) async {
    await writeAccessToken(accessToken);
    await writeRefreshToken(refreshToken);
    if (expiryMillis == null) {
      await _secure.delete(key: _keyExpiry);
    } else {
      await writeExpiryMillis(expiryMillis);
    }
    await writeEmail(email);
    await writeUserId(userId);
  }

  Future<String?> readAccessToken() => _secure.read(key: _keyAccess);
  Future<String?> readRefreshToken() => _secure.read(key: _keyRefresh);
  Future<int?> readExpiryMillis() async {
    final v = await _secure.read(key: _keyExpiry);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<String?> readEmail() => _secure.read(key: _keyEmail);
  Future<String?> readUserId() => _secure.read(key: _keyUserId);

  Future<void> clear() async {
    await _secure.delete(key: _keyAccess);
    await _secure.delete(key: _keyRefresh);
    await _secure.delete(key: _keyExpiry);
    await _secure.delete(key: _keyEmail);
    await _secure.delete(key: _keyUserId);
  }
}
