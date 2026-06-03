import 'dart:async';

import 'package:capstone_project/screens/data_consent_screen.dart';
import 'package:capstone_project/screens/pending_screen.dart';
import 'package:capstone_project/screens/profile_screen.dart';
import 'package:capstone_project/screens/history_screen.dart';
import 'package:capstone_project/screens/notification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/notification_item.dart';
import '../services/mongo_data_api_service.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  final PendingRequest? newRequest;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.newRequest,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  late PageController _pageController;
  late List<NotificationItem> _notifications;
  List<PendingRequest> _pendingRequests = [];
  List<HistoryItem> _historyItems = [];
  bool _isLoadingRequests = false;
  bool _isLoadingNotifications = false;
  bool _hasLoadedNotifications = false;
  final Set<String> _notificationIds = {};
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _selectedIndex);
    _notifications = [];
    _loadRequests();
    _loadNotifications();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadNotifications(showPopups: true),
    );
  }

  bool _isHistoryStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'completed' || normalized == 'rejected';
  }

  bool _isApprovedStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'approved' ||
        normalized == 'released' ||
        normalized == 'completed';
  }

  String _displayStatus(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty) return 'PENDING FOR PAYMENT';
    if (normalized == 'pending_payment' || normalized == 'pending for payment') {
      return 'PENDING FOR PAYMENT';
    }
    if (normalized == 'pending_completion' || normalized == 'pending to complete') {
      return 'PENDING TO COMPLETE';
    }
    return normalized.toUpperCase();
  }

  DateTime _parseRequestDate(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }

  double _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  DateTime _parseNotificationDate(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }

  String _formatNotificationTimestamp(DateTime value) {
    return DateFormat('MMM d, y h:mm a').format(value);
  }

  Future<void> _loadNotifications({bool showPopups = false}) async {
    if (_isLoadingNotifications) return;
    setState(() {
      _isLoadingNotifications = true;
    });

    try {
      final items = await MongoDataApiService.instance.fetchNotifications();
      final existingRead = {
        for (final item in _notifications) item.id: item.isRead,
      };
      final nextNotifications = <NotificationItem>[];

      for (final item in items) {
        final id = item['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final title = item['title']?.toString().trim() ?? '';
        final message = item['message']?.toString().trim() ?? '';
        if (title.isEmpty && message.isEmpty) continue;
        final createdAt = _parseNotificationDate(item['createdAt']);
        final isRead = item['isRead'] == true || existingRead[id] == true;
        nextNotifications.add(
          NotificationItem(
            id: id,
            title: title,
            message: message,
            createdAt: createdAt,
            timestamp: _formatNotificationTimestamp(createdAt),
            isRead: isRead,
          ),
        );
      }

      final nextIds = nextNotifications.map((item) => item.id).toSet();
      final newItems = _hasLoadedNotifications
          ? nextNotifications
              .where((item) => !_notificationIds.contains(item.id))
              .toList()
          : <NotificationItem>[];

      if (showPopups && newItems.isNotEmpty && mounted) {
        final headline = newItems.length == 1
            ? 'New notification: ${newItems.first.title}'
            : 'You have ${newItems.length} new notifications';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(headline)),
        );
      }

      if (!mounted) return;
      setState(() {
        _notifications = nextNotifications;
        _notificationIds
          ..clear()
          ..addAll(nextIds);
        _isLoadingNotifications = false;
        _hasLoadedNotifications = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingNotifications = false;
        _hasLoadedNotifications = true;
      });
    }
  }

  void _mergeNewRequest(List<PendingRequest> pending) {
    final newRequest = widget.newRequest;
    if (newRequest == null) return;

    final exists = pending.any((item) {
      final timeDiff = item.dateCreated
          .difference(newRequest.dateCreated)
          .inMinutes
          .abs();
      return item.docName == newRequest.docName &&
          item.purpose == newRequest.purpose &&
          timeDiff < 1;
    });

    if (!exists && !_isHistoryStatus(newRequest.status)) {
      pending.insert(0, newRequest);
    }
  }

  Future<void> _loadRequests() async {
    if (_isLoadingRequests) return;
    setState(() {
      _isLoadingRequests = true;
    });

    try {
      final items = await MongoDataApiService.instance.fetchRequests();
      final transactions = await MongoDataApiService.instance.fetchTransactions();
      final pending = <PendingRequest>[];
      final history = <HistoryItem>[];

      for (final item in items) {
        final docName = item['docName']?.toString().trim() ?? '';
        if (docName.isEmpty) continue;
        final purpose = item['purpose']?.toString().trim() ?? '';
        final statusRaw = item['status']?.toString().trim() ?? 'pending';
        final createdAt = _parseRequestDate(item['createdAt']);
        final status = _displayStatus(statusRaw);
        final documentPrice = _parseAmount(item['documentPrice']);
        final totalAmount = _parseAmount(item['totalAmount']);
        final resolvedTotal = totalAmount > 0
          ? totalAmount
          : documentPrice;

        if (!_isHistoryStatus(statusRaw)) {
          pending.add(PendingRequest(
            docName: docName,
            purpose: purpose,
            dateCreated: createdAt,
            status: status,
            documentPrice: documentPrice,
            totalAmount: resolvedTotal,
          ));
        }
      }

      for (final item in transactions) {
        final docName = item['docName']?.toString().trim() ?? '';
        if (docName.isEmpty) continue;
        final purpose = item['purpose']?.toString().trim() ?? '';
        final statusRaw = item['status']?.toString().trim() ?? 'completed';
        if (!_isHistoryStatus(statusRaw)) {
          continue;
        }
        final createdAt = _parseRequestDate(item['createdAt']);
        final status = _displayStatus(statusRaw);
        final totalAmount = _parseAmount(
          item['totalAmount'] ?? item['amount'] ?? item['documentPrice'],
        );
        final paymentType = item['paymentType']?.toString().trim() ?? '';
        history.add(HistoryItem(
          title: docName,
          date: createdAt,
          purpose: purpose,
          status: status,
          isApproved: _isApprovedStatus(statusRaw),
          totalAmount: totalAmount,
          paymentType: paymentType,
        ));
      }

      _mergeNewRequest(pending);

      if (!mounted) return;
      setState(() {
        _pendingRequests = pending;
        _historyItems = history;
        _isLoadingRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingRequests = false;
      });
    }
  }

  int get _unreadCount =>
      _notifications.where((item) => !item.isRead).length;

  void _openNotifications() {
    setState(() {
      for (final item in _notifications) {
        item.isRead = true;
      }
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            NotificationScreen(notifications: _notifications),
      ),
    );
  }


  void _onTappedBar(int value) {
    setState(() {
      _selectedIndex = value;
    });
    _pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (value == 1 || value == 2) {
      _loadRequests();
    }
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (page) {
          setState(() {
            _selectedIndex = page;
          });
          if (page == 1 || page == 2) {
            _loadRequests();
          }
        },
        children: [
          _buildHomeContent(context),
          PendingScreen(
            requestList: _isLoadingRequests ? [] : _pendingRequests,
          ),
          HistoryScreen(
            historyList: _isLoadingRequests ? [] : _historyItems,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 80.h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20.r),
            topRight: Radius.circular(20.r),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: _buildNavigationItem(Icons.home_outlined, Icons.home, 0)),
            Expanded(child: _buildNavigationItem(Icons.access_time, Icons.access_time_filled, 1)),
            Expanded(child: _buildNavigationItem(Icons.assignment_outlined, Icons.assignment, 2)),
          ],
        ),
      ),
    );
  }

  
  Widget _buildNavigationItem(IconData icon, IconData activeIcon, int index) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onTappedBar(index),
      child: Container(
        alignment: Alignment.center,
        height: 80.h,
        decoration: BoxDecoration(
          color: isSelected ? fbPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? Colors.white : fbDarkPrimary,
          size: 28.sp,
        ),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final pendingCount = _pendingRequests.length;
    final historyCount = _historyItems.length;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B3B57), Color(0xFF467599)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(28.r),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -40.h,
                  right: -30.w,
                  child: Container(
                    width: 140.r,
                    height: 140.r,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -60.h,
                  left: -20.w,
                  child: Container(
                    width: 180.r,
                    height: 180.r,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(13),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 24.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _openNotifications,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.white,
                                    radius: 20.r,
                                    child: Icon(
                                      Icons.notifications,
                                      size: 22.sp,
                                      color: fbPrimary,
                                    ),
                                  ),
                                  if (_unreadCount > 0)
                                    Positioned(
                                      right: -4.w,
                                      top: -4.h,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6.w,
                                          vertical: 2.h,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(12.r),
                                        ),
                                        child: Text(
                                          _unreadCount > 99
                                              ? '99+'
                                              : _unreadCount.toString(),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.sp,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ProfileScreen(),
                                ),
                              ),
                              child: CircleAvatar(
                                backgroundColor: Colors.white,
                                radius: 20.r,
                                child: Icon(
                                  Icons.person,
                                  size: 22.sp,
                                  color: fbPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20.h),
                        Text(
                          "Welcome back",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14.sp,
                            fontFamily: 'Frutiger',
                            letterSpacing: 0.6,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          "VerifiTOR",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34.sp,
                            fontFamily: 'Klavika',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          "Track requests, payments, and releases in one place.",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.sp,
                            fontFamily: 'Frutiger',
                          ),
                        ),
                        SizedBox(height: 18.h),
                        Row(
                          children: [
                            _buildStatPill(
                              label: 'Pending',
                              value: pendingCount.toString(),
                              color: const Color(0xFFFFC857),
                            ),
                            SizedBox(width: 10.w),
                            _buildStatPill(
                              label: 'History',
                              value: historyCount.toString(),
                              color: const Color(0xFF7BD389),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(22.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56.r,
                        height: 56.r,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF4F8),
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child:
                            const Icon(Icons.add_task, color: Color(0xFF1B3B57)),
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Make a request",
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Klavika',
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              "Submit documents in under 2 minutes.",
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.black54,
                                fontFamily: 'Frutiger',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DataConsentScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B2E3C),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.w,
                          vertical: 14.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: Text(
                        "Make Request",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(31),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: Colors.white.withAlpha(51)),
      ),
      child: Row(
        children: [
          Container(
            width: 8.r,
            height: 8.r,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 6.w),
          Text(
            "$label: $value",
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.sp,
              fontFamily: 'Frutiger',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

}