import 'package:capstone_project/screens/history_detail_screen.dart';
import 'package:capstone_project/screens/history_screen.dart';
import 'package:capstone_project/screens/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy None placeholders do not hide remarks fallback or refunds', () {
    final rejected = HistoryItem(
      transactionId: 'txn-placeholder',
      title: 'Transcript of Records',
      date: DateTime(2026, 8, 3),
      purpose: 'Employment',
      status: 'REJECTED',
      isApproved: false,
      totalAmount: 600,
      paymentType: 'gcash',
      remarks: 'None',
      refundStatus: 'None',
    );

    expect(
      rejected.displayRemarks,
      "No remarks were supplied by the Registrar's Office.",
    );
    expect(rejected.hasRefundRequest, isFalse);
    expect(rejected.canRequestRefund, isTrue);
  });

  testWidgets('pending screen distinguishes loading from an empty list',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PendingScreen(requestList: [], isLoading: true),
      ),
    );

    expect(find.byKey(const Key('pending_loading_state')), findsOneWidget);
    expect(find.text('Loading pending requests…'), findsOneWidget);
    expect(find.text('No pending requests'), findsNothing);
  });

  testWidgets('pending refresh control calls the supplied loader',
      (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PendingScreen(
          requestList: const [],
          onRefresh: () async => refreshCount++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('pending_refresh_button')));
    await tester.pump();

    expect(refreshCount, 1);
  });

  testWidgets('history empty and error states always explain what happened',
      (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          historyList: const [],
          errorMessage: 'No internet connection.',
          onRefresh: () async => refreshCount++,
        ),
      ),
    );

    expect(find.byKey(const Key('history_error_state')), findsOneWidget);
    expect(find.text('Request history could not be loaded'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history_state_try_again_button')));
    await tester.pump();
    expect(refreshCount, 1);

    await tester.pumpWidget(
      const MaterialApp(home: HistoryScreen(historyList: [])),
    );
    await tester.pump();
    expect(find.text('No request history yet'), findsOneWidget);
    expect(
      find.text('Completed and rejected requests will appear here.'),
      findsOneWidget,
    );
    expect(find.text('None'), findsNothing);
  });

  testWidgets('rejected history shows remarks fallback on card and details',
      (tester) async {
    final rejected = HistoryItem(
      title: 'Transcript of Records',
      date: DateTime(2026, 8, 3),
      purpose: 'Employment',
      status: 'REJECTED',
      isApproved: false,
      totalAmount: 0,
      paymentType: '',
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(historyList: [rejected])),
    );

    expect(find.text('Remarks'), findsOneWidget);
    expect(
      find.text("No remarks were supplied by the Registrar's Office."),
      findsOneWidget,
    );

    await tester.tap(find.text('Transcript of Records'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('history_detail_remarks')), findsOneWidget);
    expect(find.text('No payment recorded'), findsOneWidget);
    expect(
      find.text("No remarks were supplied by the Registrar's Office."),
      findsOneWidget,
    );
  });

  testWidgets('completed refund uses sent messaging', (tester) async {
    final rejected = HistoryItem(
      transactionId: 'txn-1',
      title: 'Diploma',
      date: DateTime(2026, 8, 3),
      purpose: 'Employment',
      status: 'REJECTED',
      isApproved: false,
      totalAmount: 100,
      paymentType: 'gcash',
      refundStatus: 'completed',
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryDetailScreen(item: rejected)),
    );

    expect(find.text('Refund sent'), findsOneWidget);
    expect(find.textContaining('marked your refund as sent'), findsOneWidget);
  });

  testWidgets('prefixed pending refund remains under review', (tester) async {
    final rejected = HistoryItem(
      transactionId: 'txn-2',
      title: 'Diploma',
      date: DateTime(2026, 8, 3),
      purpose: 'Employment',
      status: 'REJECTED',
      isApproved: false,
      totalAmount: 100,
      paymentType: 'gcash',
      refundStatus: 'refund_pending',
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryDetailScreen(item: rejected)),
    );

    expect(find.text('Refund under review'), findsOneWidget);
    expect(find.text('Refund sent'), findsNothing);
  });

  testWidgets('history card fits a narrow mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          historyList: [
            HistoryItem(
              title: 'Transcript of Records with Authentication',
              date: DateTime(2026, 8, 3),
              purpose: 'International employment application',
              status: 'REJECTED',
              isApproved: false,
              totalAmount: 100,
              paymentType: 'gcash',
              transactionId: 'txn-1',
              remarks: 'The submitted identification could not be validated.',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
