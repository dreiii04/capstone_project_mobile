import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants.dart';
import '../models/notification_item.dart';
import '../services/mongo_data_api_service.dart';

typedef MarkNotificationRead = Future<void> Function(String notificationId);
typedef MarkAllNotificationsRead = Future<void> Function();
typedef DismissNotification = Future<void> Function(String notificationId);

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    super.key,
    required this.notifications,
    this.onMarkRead,
    this.onMarkAllRead,
    this.onDismiss,
  });

  final List<NotificationItem> notifications;
  final MarkNotificationRead? onMarkRead;
  final MarkAllNotificationsRead? onMarkAllRead;
  final DismissNotification? onDismiss;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _filterType = 'all'; // 'all' or 'unread'
  final Set<String> _updatingIds = {};
  bool _isMarkingAll = false;

  Future<void> _markAsRead(NotificationItem notification) async {
    if (notification.isRead || _updatingIds.contains(notification.id)) return;
    setState(() => _updatingIds.add(notification.id));
    try {
      await (widget.onMarkRead ??
          MongoDataApiService.instance.markNotificationRead)(notification.id);
      if (!mounted) return;
      setState(() => notification.isRead = true);
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not mark this notification as read.');
    } finally {
      if (mounted) setState(() => _updatingIds.remove(notification.id));
    }
  }

  Future<void> _markAllAsRead() async {
    if (_isMarkingAll || !widget.notifications.any((item) => !item.isRead)) {
      return;
    }
    setState(() => _isMarkingAll = true);
    try {
      await (widget.onMarkAllRead ??
          MongoDataApiService.instance.markAllNotificationsRead)();
      if (!mounted) return;
      setState(() {
        for (final notification in widget.notifications) {
          notification.isRead = true;
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not mark all notifications as read.');
    } finally {
      if (mounted) setState(() => _isMarkingAll = false);
    }
  }

  Future<void> _dismissNotification(NotificationItem notification) async {
    if (_updatingIds.contains(notification.id)) return;
    setState(() => _updatingIds.add(notification.id));
    try {
      await (widget.onDismiss ??
          MongoDataApiService.instance.dismissNotification)(notification.id);
      if (!mounted) return;
      setState(() => widget.notifications.remove(notification));
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Could not dismiss this notification.');
    } finally {
      if (mounted) setState(() => _updatingIds.remove(notification.id));
    }
  }

  void _showError(Object error, String fallback) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isEmpty ? fallback : message)),
    );
  }

  List<NotificationItem> _getFilteredNotifications() {
    final filtered = _filterType == 'unread'
        ? widget.notifications.where((item) => !item.isRead).toList()
        : widget.notifications.toList();
    filtered.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotifications = _getFilteredNotifications();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: fbPrimary,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header with Mark All Read
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                TextButton(
                  key: const Key('mark_all_notifications_read'),
                  onPressed: _isMarkingAll ||
                          !widget.notifications.any((item) => !item.isRead)
                      ? null
                      : _markAllAsRead,
                  child: _isMarkingAll
                      ? SizedBox.square(
                          dimension: 18.r,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Mark All Read',
                          style: TextStyle(
                            color: fbPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
          // Filter Tabs
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                FilterTab(
                  label: 'All',
                  isActive: _filterType == 'all',
                  onTap: () {
                    setState(() {
                      _filterType = 'all';
                    });
                  },
                ),
                SizedBox(width: 12.w),
                FilterTab(
                  label: 'Unread',
                  isActive: _filterType == 'unread',
                  onTap: () {
                    setState(() {
                      _filterType = 'unread';
                    });
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          // Notification List
          Expanded(
            child: filteredNotifications.isEmpty
                ? Center(
                    child: Text(
                      _filterType == 'unread'
                          ? 'No unread notifications.'
                          : 'No notifications yet.',
                      style:
                          TextStyle(fontSize: 16.sp, color: Colors.grey[600]),
                    ),
                  )
                : ListView.separated(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    itemCount: filteredNotifications.length,
                    separatorBuilder: (_, __) => SizedBox(height: 12.h),
                    itemBuilder: (context, index) {
                      final item = filteredNotifications[index];
                      return NotificationItemCard(
                        key: Key('notification_${item.id}'),
                        item: item,
                        isUpdating: _updatingIds.contains(item.id),
                        onTap: () => _markAsRead(item),
                        onDismiss: () => _dismissNotification(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const FilterTab({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isActive ? fbPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: isActive
              ? null
              : Border.all(color: Colors.grey.shade300, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black87,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class NotificationItemCard extends StatelessWidget {
  final NotificationItem item;
  final bool isUpdating;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const NotificationItemCard({
    super.key,
    required this.item,
    required this.isUpdating,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.isRead ? Colors.white : const Color(0xFFF5F9FC),
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: item.isRead || isUpdating ? null : onTap,
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Unread indicator
                  Container(
                    width: 8.w,
                    height: 8.h,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.isRead ? Colors.transparent : fbPrimary,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          item.message,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          item.timestamp,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  if (isUpdating)
                    SizedBox.square(
                      dimension: 18.r,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      key: Key('dismiss_notification_${item.id}'),
                      tooltip: 'Dismiss notification',
                      onPressed: onDismiss,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 19.sp,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
