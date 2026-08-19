import 'package:capstone_project/models/request_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain pending requests still need payment', () {
    expect(displayRequestStatus('Pending'), 'PENDING FOR PAYMENT');
  });

  test('pending requests with a submitted receipt await completion', () {
    expect(
      displayRequestStatus('Pending', hasSubmittedPayment: true),
      'PENDING TO COMPLETE',
    );
    expect(
      transactionIndicatesSubmittedPayment('Pending Verification'),
      isTrue,
    );
  });

  test('rejected payment does not count as submitted payment', () {
    expect(transactionIndicatesSubmittedPayment('Rejected'), isFalse);
  });

  test('pay now is available only before a payment is submitted', () {
    expect(requestNeedsPayment('Pending'), isTrue);
    expect(requestNeedsPayment('pending-for-payment'), isTrue);
    expect(
      requestNeedsPayment('Pending', hasSubmittedPayment: true),
      isFalse,
    );
    expect(requestNeedsPayment('In Process'), isFalse);
    expect(requestNeedsPayment('Released'), isFalse);
    expect(requestNeedsPayment('Rejected'), isFalse);
  });
}
