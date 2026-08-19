import 'package:capstone_project/models/notification_item.dart';
import 'package:capstone_project/screens/notification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notifications show the latest item first', (tester) async {
    tester.view.physicalSize = const Size(412, 715);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notifications = [
      NotificationItem(
        id: 'oldest',
        title: 'Oldest update',
        message: 'First message',
        timestamp: 'Aug 8, 2026 9:00 AM',
        createdAt: DateTime(2026, 8, 8, 9),
      ),
      NotificationItem(
        id: 'latest',
        title: 'Latest update',
        message: 'Newest message',
        timestamp: 'Aug 10, 2026 9:00 AM',
        createdAt: DateTime(2026, 8, 10, 9),
      ),
      NotificationItem(
        id: 'middle',
        title: 'Middle update',
        message: 'Second message',
        timestamp: 'Aug 9, 2026 9:00 AM',
        createdAt: DateTime(2026, 8, 9, 9),
      ),
    ];

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(412, 715),
        builder: (_, __) => MaterialApp(
          home: NotificationScreen(notifications: notifications),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final latestTop = tester.getTopLeft(find.text('Latest update')).dy;
    final middleTop = tester.getTopLeft(find.text('Middle update')).dy;
    final oldestTop = tester.getTopLeft(find.text('Oldest update')).dy;

    expect(latestTop, lessThan(middleTop));
    expect(middleTop, lessThan(oldestTop));
  });

  testWidgets('opening the list does not read an item; tapping it does',
      (tester) async {
    tester.view.physicalSize = const Size(412, 715);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notification = NotificationItem(
      id: 'unread-item',
      title: 'Request update',
      message: 'Your request is ready.',
      timestamp: 'Aug 19, 2026 9:00 AM',
      createdAt: DateTime(2026, 8, 19, 9),
    );
    String? markedId;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(412, 715),
        builder: (_, __) => MaterialApp(
          home: NotificationScreen(
            notifications: [notification],
            onMarkRead: (id) async => markedId = id,
            onMarkAllRead: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(notification.isRead, isFalse);
    await tester.tap(find.byKey(const Key('notification_unread-item')));
    await tester.pumpAndSettle();
    expect(markedId, 'unread-item');
    expect(notification.isRead, isTrue);

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('No unread notifications.'), findsOneWidget);
  });

  testWidgets('mark all read persists before updating local state',
      (tester) async {
    tester.view.physicalSize = const Size(412, 715);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifications = [
      NotificationItem(
        id: 'one',
        title: 'One',
        message: 'First',
        timestamp: 'Now',
        createdAt: DateTime(2026, 8, 19),
      ),
      NotificationItem(
        id: 'two',
        title: 'Two',
        message: 'Second',
        timestamp: 'Now',
        createdAt: DateTime(2026, 8, 19),
      ),
    ];
    var persisted = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(412, 715),
        builder: (_, __) => MaterialApp(
          home: NotificationScreen(
            notifications: notifications,
            onMarkRead: (_) async {},
            onMarkAllRead: () async => persisted = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark_all_notifications_read')));
    await tester.pumpAndSettle();

    expect(persisted, isTrue);
    expect(notifications.every((item) => item.isRead), isTrue);
  });

  testWidgets('close button persists dismissal and removes the notification',
      (tester) async {
    tester.view.physicalSize = const Size(412, 715);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifications = [
      NotificationItem(
        id: 'dismiss-me',
        title: 'Dismissible update',
        message: 'This notification can be closed.',
        timestamp: 'Now',
        createdAt: DateTime(2026, 8, 19),
      ),
    ];
    String? dismissedId;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(412, 715),
        builder: (_, __) => MaterialApp(
          home: NotificationScreen(
            notifications: notifications,
            onMarkRead: (_) async {},
            onMarkAllRead: () async {},
            onDismiss: (id) async => dismissedId = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('dismiss_notification_dismiss-me')),
    );
    await tester.pumpAndSettle();

    expect(dismissedId, 'dismiss-me');
    expect(notifications, isEmpty);
    expect(find.text('No notifications yet.'), findsOneWidget);
  });
}
