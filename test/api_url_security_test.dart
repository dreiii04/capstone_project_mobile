import 'package:capstone_project/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses only the centralized deployed API', () {
    expect(
      ApiConstants.baseUrl,
      'https://verifitor-backend.vercel.app/api',
    );
  });

  test('builds every endpoint from the centralized base URL', () {
    for (final path in [
      '/auth/login',
      '/auth/register/request-otp',
      '/profile',
      '/requests',
      '/notifications',
      '/transactions',
      '/refunds',
    ]) {
      expect(
        ApiConstants.uri(path).toString(),
        '${ApiConstants.baseUrl}$path',
      );
    }
  });
}
