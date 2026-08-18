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
}
