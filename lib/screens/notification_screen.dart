import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants.dart';
import '../models/notification_item.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    super.key,
    required this.notifications,
  });

  final List<NotificationItem> notifications;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _filterType = 'all'; // 'all' or 'unread'

  void _removeNotification(int index) {
    setState(() {
      widget.notifications.removeAt(index);
    });
  }

  void _markAllAsRead() {
    setState(() {
      for (var notification in widget.notifications) {
        notification.isRead = true;
      }
    });
  }

  List<NotificationItem> _getFilteredNotifications() {
    if (_filterType == 'unread') {
      return widget.notifications.where((n) => !n.isRead).toList();
    }
    return widget.notifications;
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
                  onPressed: _markAllAsRead,
                  child: Text(
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
                      style: TextStyle(fontSize: 16.sp, color: Colors.grey[600]),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    itemCount: filteredNotifications.length,
                    separatorBuilder: (_, __) => SizedBox(height: 12.h),
                    itemBuilder: (context, index) {
                      final item = filteredNotifications[index];
                      final originalIndex = widget.notifications.indexOf(item);
                      return NotificationItemCard(
                        item: item,
                        onRemove: () => _removeNotification(originalIndex),
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
  final VoidCallback onRemove;

  const NotificationItemCard({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  size: 18.sp,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
