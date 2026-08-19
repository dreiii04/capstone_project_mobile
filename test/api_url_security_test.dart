import 'package:capstone_project/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses only the centralized deployed API', () {
    expect(
      ApiConstants.baseUrl,
      'https://cp-three-lemon.vercel.app/api',
    );
  });

  test('builds every endpoint from the centralized base URL', () {
    for (final path in [
      '/auth/login',
      '/auth/register/request-otp',
      '/auth/profile',
      '/requests',
      '/notifications',
      '/transactions',
      '/transactions/refund-request',
    ]) {
      expect(
        ApiConstants.uri(path).toString(),
        '${ApiConstants.baseUrl}$path',
      );
    }
  });
}
