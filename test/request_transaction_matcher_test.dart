import 'package:capstone_project/models/request_transaction_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final request = <String, dynamic>{
    'requestId': 'REQ-CURRENT',
    'docName': 'Certified True Copy (CTC)',
    'purpose': 'Board Exam',
    'createdAt': '2026-08-19T06:28:00.000Z',
  };

  test('same document and purpose cannot override a request ID mismatch', () {
    expect(
      requestMatchesTransaction(request, {
        'requestId': 'REQ-SOMEONE-ELSE',
        'docName': 'Certified True Copy (CTC)',
        'purpose': 'Board Exam',
        'createdAt': '2026-08-19T06:28:30.000Z',
      }),
      isFalse,
    );
  });

  test('a transaction with the same request ID is accepted', () {
    expect(
      requestMatchesTransaction(request, {
        'requestId': 'REQ-CURRENT',
        'docName': 'Certified True Copy (CTC)',
        'purpose': 'Board Exam',
        'createdAt': '2026-08-19T06:28:30.000Z',
      }),
      isTrue,
    );
  });

  test('legacy records match only within a short time window', () {
    final legacyRequest = Map<String, dynamic>.from(request)
      ..remove('requestId');
    expect(
      requestMatchesTransaction(legacyRequest, {
        'docName': 'Certified True Copy (CTC)',
        'purpose': 'Board Exam',
        'createdAt': '2026-08-18T06:28:00.000Z',
      }),
      isFalse,
    );
  });
}
