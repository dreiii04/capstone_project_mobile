import 'package:capstone_project/screens/history_detail_screen.dart';
import 'package:capstone_project/screens/history_screen.dart';
import 'package:capstone_project/screens/payment_refund_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryItem _historyItem({
  String status = 'REJECTED',
  double amount = 600,
  String paymentType = 'gcash',
  String transactionId = 'transaction-1',
  String refundStatus = '',
}) {
  return HistoryItem(
    transactionId: transactionId,
    title: 'Transcript of Records (TOR)',
    date: DateTime(2026, 7, 27),
    purpose: 'Employment',
    status: status,
    isApproved: false,
    totalAmount: amount,
    paymentType: paymentType,
    refundStatus: refundStatus,
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('paid rejected request exposes the refund screen',
      (tester) async {
    await _setSize(tester, const Size(412, 715));
    await tester.pumpWidget(
      MaterialApp(home: HistoryDetailScreen(item: _historyItem())),
    );
    await tester.pumpAndSettle();

    final refundButton = find.byKey(const Key('request_refund_button'));
    expect(refundButton, findsOneWidget);
    await tester.ensureVisible(refundButton);
    await tester.tap(refundButton);
    await tester.pumpAndSettle();

    expect(find.byType(PaymentRefundScreen), findsOneWidget);
    expect(find.text('Refund summary'), findsOneWidget);
    expect(find.text('How the refund works'), findsOneWidget);
    expect(find.text('PHP 600.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unpaid rejected request does not expose a refund action',
      (tester) async {
    await _setSize(tester, const Size(412, 715));
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailScreen(
          item: _historyItem(amount: 0, paymentType: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('request_refund_button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refund form fits a portrait tablet', (tester) async {
    await _setSize(tester, const Size(800, 1280));
    await tester.pumpWidget(
      MaterialApp(home: PaymentRefundScreen(item: _historyItem())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Refund destination'), findsOneWidget);
    expect(find.byKey(const Key('submit_refund_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
