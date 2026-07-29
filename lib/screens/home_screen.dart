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
    if (normalized == 'pending_payment' ||
        normalized == 'pending for payment') {
      return 'PENDING FOR PAYMENT';
    }
    if (normalized == 'pending_completion' ||
        normalized == 'pending to complete') {
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
      final timeDiff =
          item.dateCreated.difference(newRequest.dateCreated).inMinutes.abs();
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
      final transactions =
          await MongoDataApiService.instance.fetchTransactions();
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
        final resolvedTotal = totalAmount > 0 ? totalAmount : documentPrice;

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
        final transactionId = item['id']?.toString().trim() ?? '';
        final refundStatus = item['refundStatus']?.toString().trim() ?? '';
        history.add(HistoryItem(
          transactionId: transactionId,
          title: docName,
          date: createdAt,
          purpose: purpose,
          status: status,
          isApproved: _isApprovedStatus(statusRaw),
          totalAmount: totalAmount,
          paymentType: paymentType,
          refundStatus: refundStatus,
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

  int get _unreadCount => _notifications.where((item) => !item.isRead).length;

  void _openNotifications() {
    setState(() {
      for (final item in _notifications) {
        item.isRead = true;
      }
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationScreen(notifications: _notifications),
      ),
    );
  }

  void _openProfile() {
    _onTappedBar(3);
  }

  Future<void> _refreshHome() async {
    await Future.wait([
      _loadRequests(),
      _loadNotifications(),
    ]);
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
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
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
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: isTablet ? 76 : 70.h,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onTappedBar,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFDDEAF2),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.schedule_outlined),
                selectedIcon: Icon(Icons.schedule),
                label: 'Pending',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final pendingCount = _pendingRequests.length;
    final historyCount = _historyItems.length;
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return RefreshIndicator(
      color: fbPrimary,
      onRefresh: _refreshHome,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 28 : 18.w,
                  isTablet ? 20 : 12.h,
                  isTablet ? 28 : 18.w,
                  isTablet ? 36 : 28.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReferenceTopBar(),
                    SizedBox(height: isTablet ? 24 : 18.h),
                    _buildRequestOverview(
                      pendingCount: pendingCount,
                      historyCount: historyCount,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferenceTopBar() {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Open profile',
          child: Material(
            color: const Color(0xFFE7EEF3),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _openProfile,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: isTablet ? 52 : 45.r,
                height: isTablet ? 52 : 45.r,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: fbDarkPrimary,
                  size: isTablet ? 28 : 25.sp,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: isTablet ? 14 : 11.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome',
                style: TextStyle(
                  color: const Color(0xFF7A858D),
                  fontFamily: 'Frutiger',
                  fontSize: isTablet ? 13 : 10.sp,
                ),
              ),
              SizedBox(height: 3.h),
              Image.asset(
                'assets/logo/logo.png',
                width: isTablet ? 150 : 128.w,
                height: isTablet ? 40 : 34.h,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ],
          ),
        ),
        _buildTopActionButton(
          icon: Icons.notifications_none_rounded,
          label: _unreadCount == 0
              ? 'Open notifications'
              : 'Open notifications, $_unreadCount unread',
          badge: _unreadCount,
          onTap: _openNotifications,
        ),
      ],
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: isTablet ? 48 : 41.r,
                height: isTablet ? 48 : 41.r,
                child: Icon(
                  icon,
                  size: isTablet ? 24 : 21.sp,
                  color: fbDarkPrimary,
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    width: 9.r,
                    height: 9.r,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5A6F),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestOverview({
    required int pendingCount,
    required int historyCount,
  }) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Container(
      width: double.infinity,
      height: isTablet ? 285 : 245.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF73899A).withAlpha(48),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: Container(
          padding: EdgeInsets.all(isTablet ? 24 : 18.r),
          decoration: const BoxDecoration(color: Color(0xFF5A819B)),
          child: Stack(
            children: [
              Positioned(
                right: -28.r,
                bottom: -38.r,
                child: Container(
                  width: 145.r,
                  height: 145.r,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(13),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 2.w,
                      vertical: 4.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'My requests',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Klavika',
                                fontSize: isTablet ? 21 : 16.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            _buildOverviewIcon(
                              Icons.refresh_rounded,
                              onTap: _refreshHome,
                            ),
                          ],
                        ),
                        SizedBox(height: isTablet ? 18 : 12.h),
                        Row(
                          children: [
                            Expanded(
                              child: _buildOverviewMetric(
                                label: 'Active',
                                value: pendingCount.toString(),
                                suffix:
                                    pendingCount == 1 ? 'request' : 'requests',
                              ),
                            ),
                            Container(
                              width: 1,
                              height: isTablet ? 50 : 40.h,
                              color: Colors.white30,
                            ),
                            SizedBox(width: isTablet ? 26 : 18.w),
                            Expanded(
                              child: _buildOverviewMetric(
                                label: 'Records',
                                value: historyCount.toString(),
                                suffix: 'history',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isTablet ? 44 : 36.h),
                  Text(
                    'Ready for your next document?',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Klavika',
                      fontSize: isTablet ? 22 : 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: isTablet ? 22 : 18.h),
                  Align(
                    alignment: Alignment.center,
                    child: Material(
                      color: const Color(0xFFC8F36B),
                      borderRadius: BorderRadius.circular(22.r),
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DataConsentScreen(),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(22.r),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 30 : 24.w,
                            vertical: isTablet ? 13 : 11.h,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: const Color(0xFF2E3B0A),
                                size: isTablet ? 21 : 18.sp,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'New request',
                                style: TextStyle(
                                  color: const Color(0xFF2E3B0A),
                                  fontFamily: 'Frutiger',
                                  fontSize: isTablet ? 14 : 11.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildOverviewIcon(IconData icon, {VoidCallback? onTap}) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Material(
      color: Colors.white.withAlpha(25),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 8 : 6.r),
          child: Icon(
            icon,
            color: Colors.white,
            size: isTablet ? 19 : 15.sp,
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewMetric({
    required String label,
    required String value,
    required String suffix,
  }) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontFamily: 'Frutiger',
            fontSize: isTablet ? 15 : 11.sp,
          ),
        ),
        SizedBox(height: isTablet ? 4 : 2.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Klavika',
                fontSize: isTablet ? 34 : 27.sp,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: isTablet ? 7 : 5.w),
            Padding(
              padding: EdgeInsets.only(bottom: isTablet ? 3 : 2.h),
              child: Text(
                suffix,
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Frutiger',
                  fontSize: isTablet ? 12 : 9.sp,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
