import 'package:capstone_project/services/api_contract_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads raw and wrapped API collections', () {
    expect(
      apiList({
        'items': [
          {'_id': '1'}
        ],
      }, key: 'requests'),
      [
        {'_id': '1'}
      ],
    );
    expect(
      apiList({
        'requests': [
          {'_id': '2'}
        ],
      }, key: 'requests'),
      [
        {'_id': '2'}
      ],
    );
  });

  test('normalizes the shared backend profile contract', () {
    final profile = normalizeProfileRecord({
      '_id': 'user-1',
      'email': 'student@example.com',
      'role': 'student',
      'course': 'BSIT',
      'profilePic': 'https://example.com/photo.png',
    });

    expect(profile['id'], 'user-1');
    expect(profile['program'], 'BSIT');
    expect(profile['schoolEmail'], 'student@example.com');
    expect(profile['profileImageUrl'], 'https://example.com/photo.png');
  });

  test('normalizes requests, transactions, and notifications', () {
    final request = normalizeRequestRecord({
      '_id': 'request-1',
      'documentType': 'Transcript of Records (TOR)',
      'dateRequested': '2026-08-19T00:00:00.000Z',
    });
    final transaction = normalizeTransactionRecord({
      '_id': 'transaction-1',
      'documentType': 'Transcript',
      'paymentMode': 'GCash',
      'amount': '600.00',
      'date': '2026-08-19T00:00:00.000Z',
    });
    final notification = normalizeNotificationRecord({
      '_id': 'notification-1',
      'message': 'Ready for pickup',
      'date': '2026-08-19T00:00:00.000Z',
    });

    expect(request['docName'], 'Transcript of Records (TOR)');
    expect(request['createdAt'], '2026-08-19T00:00:00.000Z');
    expect(request['documentPrice'], 600);
    expect(request['totalAmount'], 600);
    expect(transaction['docName'], 'Transcript');
    expect(transaction['paymentType'], 'GCash');
    expect(transaction['totalAmount'], '600.00');
    expect(notification['id'], 'notification-1');
    expect(notification['title'], 'Notification');
  });

  test('repairs placeholder zero amounts in old request records', () {
    final request = normalizeRequestRecord({
      'documentType': 'Certificate of Enrollment',
      'documentPrice': 0,
      'totalAmount': '0.00',
    });

    expect(request['documentPrice'], 250);
    expect(request['totalAmount'], 250);
  });
}
