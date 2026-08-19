import 'dart:async';

import 'package:capstone_project/screens/data_consent_screen.dart';
import 'package:capstone_project/screens/pending_screen.dart';
import 'package:capstone_project/screens/profile_screen.dart';
import 'package:capstone_project/screens/history_screen.dart';
import 'package:capstone_project/screens/notification_screen.dart';
import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/models/api_date_time.dart';
import 'package:capstone_project/models/request_status.dart';
import 'package:capstone_project/models/request_transaction_matcher.dart';
import 'package:capstone_project/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/notification_item.dart';
import '../services/mongo_data_api_service.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  final ProfileData? initialProfile;

  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.initialProfile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  late PageController _pageController;
  late List<NotificationItem> _notifications;
  List<PendingRequest> _pendingRequests = [];
  List<HistoryItem> _trackingRefundItems = [];
  List<HistoryItem> _historyItems = [];
  bool _isLoadingRequests = false;
  String? _pendingRequestsError;
  String? _historyRequestsError;
  Future<void>? _requestLoad;
  bool _isLoadingNotifications = false;
  bool _hasLoadedNotifications = false;
  final Set<String> _notificationIds = {};
  Timer? _notificationTimer;
  ProfileData? _profileSummary;
  bool _isLoadingProfile = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _selectedIndex);
    _notifications = [];
    _profileSummary = widget.initialProfile;
    _loadRequests();
    _loadNotifications();
    if (widget.initialProfile == null) {
      _loadProfileSummary();
    }
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadNotifications(showPopups: true),
    );
  }

  bool _isHistoryStatus(String status) {
    final normalized = status.trim().toLowerCase().replaceAll('-', '_');
    return const {
      'complete',
      'completed',
      'approved',
      'released',
      'rejected',
      'declined',
      'denied',
      'cancelled',
      'canceled',
    }.contains(normalized);
  }

  bool _isApprovedStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'complete' ||
        normalized == 'approved' ||
        normalized == 'released' ||
        normalized == 'completed';
  }

  String _displayStatus(
    String status, {
    bool hasSubmittedPayment = false,
  }) {
    return displayRequestStatus(
      status,
      hasSubmittedPayment: hasSubmittedPayment,
    );
  }

  DateTime _parseRequestDate(dynamic value) {
    return parseApiDateTime(value);
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
    return parseApiDateTime(value);
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
      nextNotifications.sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });

      final nextIds = nextNotifications.map((item) => item.id).toSet();
      final newItems = _hasLoadedNotifications
          ? nextNotifications
              .where((item) => !_notificationIds.contains(item.id))
              .toList()
          : <NotificationItem>[];

      if (showPopups && newItems.isNotEmpty && mounted) {
        final firstNotification = newItems.first;
        final firstSummary = firstNotification.title.trim().isNotEmpty
            ? firstNotification.title.trim()
            : firstNotification.message.trim();
        final headline = newItems.length == 1
            ? 'Request update: $firstSummary'
            : 'You have ${newItems.length} new request updates';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(headline)),
        );
        unawaited(_loadRequests());
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

  String _firstText(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  String _recordRequestId(Map<String, dynamic> item) {
    return _firstText(
      item,
      const ['requestId', 'linkedRequestId', 'documentRequestId'],
    );
  }

  String _recordRemarks(Map<String, dynamic> item) {
    return _firstText(
      item,
      const [
        'remarks',
        'rejectionReason',
        'remark',
        'adminRemarks',
        'officeRemarks',
      ],
    );
  }

  String _normalizedValue(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  String _firstMeaningfulStatus(Iterable<dynamic> values) {
    const placeholders = {
      'none',
      'null',
      'n/a',
      'na',
      '_',
      'not_applicable',
    };
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      final normalized = text.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
      if (text.isNotEmpty && !placeholders.contains(normalized)) return text;
    }
    return '';
  }

  int? _matchingTransactionIndex(
    Map<String, dynamic> request,
    List<Map<String, dynamic>> transactions,
    Set<int> consumed,
  ) {
    for (var index = 0; index < transactions.length; index++) {
      if (consumed.contains(index)) continue;
      if (requestMatchesTransaction(request, transactions[index])) return index;
    }
    return null;
  }

  HistoryItem _historyFromRequest(
    Map<String, dynamic> request,
    Map<String, dynamic>? transaction,
  ) {
    final statusRaw = request['status']?.toString().trim() ?? 'completed';
    final transactionAmount = transaction == null
        ? null
        : transaction['totalAmount'] ??
            transaction['amount'] ??
            transaction['documentPrice'];
    final requestAmount =
        request['totalAmount'] ?? request['amount'] ?? request['documentPrice'];
    final requestPaymentType =
        _firstText(request, const ['paymentType', 'paymentMode']);
    final paymentType = transaction == null
        ? requestPaymentType
        : _firstText(transaction, const ['paymentType', 'paymentMode']);
    final hasPaymentRecord = transaction != null ||
        request['paymentReceived'] == true ||
        requestPaymentType.isNotEmpty;
    final requestRemarks = _recordRemarks(request);
    final transactionRemarks =
        transaction == null ? '' : _recordRemarks(transaction);

    return HistoryItem(
      requestId: _recordRequestId(request).isNotEmpty
          ? _recordRequestId(request)
          : _firstText(request, const ['id']),
      transactionId: transaction == null
          ? _firstText(request, const ['transactionId'])
          : _firstText(transaction, const ['id', 'transactionId']),
      title: request['docName']?.toString().trim() ?? '',
      date: _parseRequestDate(request['createdAt']),
      purpose: request['purpose']?.toString().trim() ?? '',
      status: _displayStatus(statusRaw),
      isApproved: _isApprovedStatus(statusRaw),
      totalAmount: hasPaymentRecord
          ? _parseAmount(transactionAmount ?? requestAmount)
          : 0,
      paymentType: paymentType,
      remarks: requestRemarks.isNotEmpty ? requestRemarks : transactionRemarks,
      refundStatus: _firstMeaningfulStatus([
        if (transaction != null) transaction['refundStatus'],
        request['refundStatus'],
      ]),
    );
  }

  _MappedRequestData _mapRequestData(
    List<Map<String, dynamic>> requests,
    List<Map<String, dynamic>> transactions,
  ) {
    final pending = <PendingRequest>[];
    final trackingRefunds = <HistoryItem>[];
    final history = <HistoryItem>[];
    final usableTransactions = transactions
        .where((item) =>
            _normalizedValue(item['docName']).isNotEmpty ||
            _recordRequestId(item).isNotEmpty)
        .toList();
    final consumedTransactions = <int>{};

    for (final item in requests) {
      final docName = item['docName']?.toString().trim() ?? '';
      if (docName.isEmpty) continue;
      final purpose = item['purpose']?.toString().trim() ?? '';
      final statusRaw = item['status']?.toString().trim() ?? 'pending';
      final createdAt = _parseRequestDate(item['createdAt']);
      final transactionIndex = _matchingTransactionIndex(
        item,
        usableTransactions,
        consumedTransactions,
      );
      final transaction = transactionIndex == null
          ? null
          : usableTransactions[transactionIndex];
      final hasSubmittedPayment = transaction != null &&
          transactionIndicatesSubmittedPayment(
            transaction['status']?.toString() ?? '',
          );
      final status = _displayStatus(
        statusRaw,
        hasSubmittedPayment: hasSubmittedPayment,
      );
      final documentPrice = _parseAmount(item['documentPrice']);
      final totalAmount = _parseAmount(item['totalAmount']);
      final resolvedTotal = totalAmount > 0 ? totalAmount : documentPrice;
      final linkedRequestId = _recordRequestId(item);
      final requestId = linkedRequestId.isNotEmpty
          ? linkedRequestId
          : _firstText(item, const ['id', '_id']);

      if (_isHistoryStatus(statusRaw)) {
        if (transactionIndex != null) {
          consumedTransactions.add(transactionIndex);
        }
        final terminalItem = _historyFromRequest(item, transaction);
        if (terminalItem.shouldTrackRefund) {
          trackingRefunds.add(terminalItem);
        } else {
          history.add(terminalItem);
        }
      } else {
        if (hasSubmittedPayment && transactionIndex != null) {
          consumedTransactions.add(transactionIndex);
        }
        pending.add(
          PendingRequest(
            requestId: requestId.isEmpty ? null : requestId,
            docName: docName,
            purpose: purpose,
            dateCreated: createdAt,
            status: status,
            documentPrice: documentPrice,
            totalAmount: resolvedTotal,
          ),
        );
      }
    }

    pending.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    trackingRefunds.sort((a, b) => b.date.compareTo(a.date));
    history.sort((a, b) => b.date.compareTo(a.date));
    return _MappedRequestData(
      pending: pending,
      trackingRefunds: trackingRefunds,
      history: history,
    );
  }

  int? _matchingHistoryIndex(
    HistoryItem item,
    List<HistoryItem> candidates,
    Set<int> consumed,
  ) {
    final requestId = _normalizedValue(item.requestId);
    final transactionId = _normalizedValue(item.transactionId);
    for (var index = 0; index < candidates.length; index++) {
      if (consumed.contains(index)) continue;
      final candidate = candidates[index];
      if ((requestId.isNotEmpty &&
              requestId == _normalizedValue(candidate.requestId)) ||
          (transactionId.isNotEmpty &&
              transactionId == _normalizedValue(candidate.transactionId))) {
        return index;
      }
    }

    int? closestIndex;
    Duration? closestDistance;
    for (var index = 0; index < candidates.length; index++) {
      if (consumed.contains(index)) continue;
      final candidate = candidates[index];
      if (_normalizedValue(candidate.title) != _normalizedValue(item.title) ||
          _normalizedValue(candidate.purpose) !=
              _normalizedValue(item.purpose)) {
        continue;
      }
      final distance = candidate.date.difference(item.date).abs();
      if (closestDistance == null || distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    return closestIndex;
  }

  HistoryItem _combineHistoryItems(HistoryItem primary, HistoryItem fallback) {
    final paymentType = primary.paymentType.trim().isNotEmpty
        ? primary.paymentType
        : fallback.paymentType;
    return HistoryItem(
      requestId: primary.requestId.trim().isNotEmpty
          ? primary.requestId
          : fallback.requestId,
      transactionId: primary.transactionId.trim().isNotEmpty
          ? primary.transactionId
          : fallback.transactionId,
      title: primary.title,
      date: primary.date,
      purpose: primary.purpose,
      status: primary.status,
      isApproved: primary.isApproved,
      totalAmount:
          primary.totalAmount > 0 ? primary.totalAmount : fallback.totalAmount,
      paymentType: paymentType,
      remarks: primary.hasRemarks ? primary.remarks : fallback.remarks,
      refundStatus: primary.hasRefundRequest
          ? primary.refundStatus
          : fallback.refundStatus,
    );
  }

  List<HistoryItem> _mergeHistoryLists(
    List<HistoryItem> primary,
    List<HistoryItem> fallback,
  ) {
    final merged = <HistoryItem>[];
    final consumedFallback = <int>{};
    for (final item in primary) {
      final match = _matchingHistoryIndex(item, fallback, consumedFallback);
      if (match == null) {
        merged.add(item);
      } else {
        consumedFallback.add(match);
        merged.add(_combineHistoryItems(item, fallback[match]));
      }
    }
    for (var index = 0; index < fallback.length; index++) {
      if (!consumedFallback.contains(index)) merged.add(fallback[index]);
    }
    merged.sort((a, b) => b.date.compareTo(a.date));
    return merged;
  }

  bool _sameRequestRecord(HistoryItem first, HistoryItem second) {
    final firstRequestId = _normalizedValue(first.requestId);
    final secondRequestId = _normalizedValue(second.requestId);
    if (firstRequestId.isNotEmpty && firstRequestId == secondRequestId) {
      return true;
    }
    final firstTransactionId = _normalizedValue(first.transactionId);
    final secondTransactionId = _normalizedValue(second.transactionId);
    if (firstTransactionId.isNotEmpty &&
        firstTransactionId == secondTransactionId) {
      return true;
    }
    return firstRequestId.isEmpty &&
        secondRequestId.isEmpty &&
        firstTransactionId.isEmpty &&
        secondTransactionId.isEmpty &&
        _normalizedValue(first.title) == _normalizedValue(second.title) &&
        _normalizedValue(first.purpose) == _normalizedValue(second.purpose) &&
        first.date.difference(second.date).inMinutes.abs() < 1;
  }

  List<HistoryItem> _withoutTrackedRefunds(
    List<HistoryItem> history,
    List<HistoryItem> trackedRefunds,
  ) {
    if (trackedRefunds.isEmpty) return history;
    return history
        .where(
          (item) => !trackedRefunds.any(
            (tracked) => _sameRequestRecord(item, tracked),
          ),
        )
        .toList();
  }

  Future<_RequestListLoad> _captureRequestLoad(
    Future<List<Map<String, dynamic>>> operation,
  ) async {
    try {
      return _RequestListLoad(data: await operation);
    } catch (error) {
      return _RequestListLoad(error: error);
    }
  }

  String _loadErrorMessage(Object? error, String fallback) {
    if (error == null) return fallback;
    final message =
        error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return message.isEmpty ? fallback : message;
  }

  Future<void> _loadRequests() async {
    final activeLoad = _requestLoad;
    if (activeLoad != null) return activeLoad;

    final load = _performRequestLoad();
    _requestLoad = load;
    try {
      await load;
    } finally {
      if (identical(_requestLoad, load)) _requestLoad = null;
    }
  }

  Future<void> _performRequestLoad() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRequests = true;
      _pendingRequestsError = null;
      _historyRequestsError = null;
    });

    final service = MongoDataApiService.instance;
    final results = await Future.wait<_RequestListLoad>([
      _captureRequestLoad(service.fetchRequests()),
      _captureRequestLoad(service.fetchTransactions()),
    ]);
    final requestResult = results[0];
    final transactionResult = results[1];

    List<PendingRequest>? nextPending;
    List<HistoryItem>? nextTrackingRefunds;
    List<HistoryItem>? nextHistory;
    if (requestResult.data != null) {
      final mapped = _mapRequestData(
        requestResult.data!,
        transactionResult.data ?? const <Map<String, dynamic>>[],
      );
      nextPending = mapped.pending;
      nextTrackingRefunds = transactionResult.data == null
          ? _mergeHistoryLists(
              mapped.trackingRefunds,
              _trackingRefundItems,
            )
          : mapped.trackingRefunds;
      final candidateHistory = transactionResult.data == null
          ? _mergeHistoryLists(mapped.history, _historyItems)
          : mapped.history;
      nextHistory = _withoutTrackedRefunds(
        candidateHistory,
        nextTrackingRefunds,
      );
    } else if (transactionResult.data != null) {
      final transactionData = _mapRequestData(
        const <Map<String, dynamic>>[],
        transactionResult.data!,
      );
      nextTrackingRefunds = transactionData.trackingRefunds;
      nextHistory = _withoutTrackedRefunds(
        _mergeHistoryLists(transactionData.history, _historyItems),
        nextTrackingRefunds,
      );
    }

    if (!mounted) return;
    setState(() {
      if (nextPending != null) _pendingRequests = nextPending;
      if (nextTrackingRefunds != null) {
        _trackingRefundItems = nextTrackingRefunds;
      }
      if (nextHistory != null) _historyItems = nextHistory;
      _pendingRequestsError = requestResult.data == null
          ? _loadErrorMessage(
              requestResult.error,
              'Tracked requests could not be refreshed. Please try again.',
            )
          : null;
      if (requestResult.data == null && transactionResult.data == null) {
        _historyRequestsError = _loadErrorMessage(
          requestResult.error ?? transactionResult.error,
          'Request history could not be refreshed. Please try again.',
        );
      } else if (requestResult.data == null) {
        _historyRequestsError =
            'Some request records could not be refreshed. Showing the latest available history.';
      } else if (transactionResult.data == null) {
        _historyRequestsError =
            'Payment and refund updates could not be refreshed. Showing available request history.';
      } else {
        _historyRequestsError = null;
      }
      _isLoadingRequests = false;
    });
  }

  int get _unreadCount => _notifications.where((item) => !item.isRead).length;

  Future<void> _loadProfileSummary() async {
    if (_isLoadingProfile) return;
    _isLoadingProfile = true;
    try {
      final profile = await MongoDataApiService.instance.fetchProfile();
      if (!mounted) return;
      setState(() => _profileSummary = profile);
    } catch (_) {
      // Keep the fallback avatar when profile data is temporarily unavailable.
    } finally {
      _isLoadingProfile = false;
    }
  }

  void _handleProfileChanged(ProfileData profile) {
    if (!mounted) return;
    setState(() => _profileSummary = profile);
    // Requests are owned by user ID/email, so a display-name change must not
    // affect visibility. Refresh immediately to verify the server-side view.
    unawaited(_loadRequests());
  }

  Future<void> _openNotifications() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationScreen(notifications: _notifications),
      ),
    );
    if (mounted) {
      await Future.wait([_loadNotifications(), _loadRequests()]);
    }
  }

  void _openProfile() {
    _onTappedBar(3);
  }

  Future<void> _refreshHome() async {
    await Future.wait([
      _loadRequests(),
      _loadNotifications(),
      _loadProfileSummary(),
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
    } else if (value == 0) {
      _loadProfileSummary();
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
          } else if (page == 0) {
            _loadProfileSummary();
          }
        },
        children: [
          _buildHomeContent(context),
          PendingScreen(
            requestList: _pendingRequests,
            refundItems: _trackingRefundItems,
            isLoading: _isLoadingRequests,
            errorMessage: _pendingRequestsError,
            onRefresh: _loadRequests,
          ),
          HistoryScreen(
            historyList: _historyItems,
            isLoading: _isLoadingRequests,
            errorMessage: _historyRequestsError,
            onRefresh: _loadRequests,
          ),
          ProfileScreen(
            onBack: () => _onTappedBar(0),
            onProfileChanged: _handleProfileChanged,
          ),
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
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Tracking',
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
    final pendingCount = _pendingRequests.length + _trackingRefundItems.length;
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
                    SizedBox(height: isTablet ? 36 : 30.h),
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
    final avatarSize = isTablet ? 62.0 : 54.0;
    final firstName = _profileSummary?.firstName.trim() ?? '';
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final welcomeMessage =
        firstName.isEmpty ? '$timeGreeting!' : '$timeGreeting, $firstName!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          key: const Key('home_identity_row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              button: true,
              excludeSemantics: true,
              label: _profileSummary == null
                  ? 'Open profile'
                  : 'Open ${_profileSummary!.fullName} profile',
              child: Material(
                color: const Color(0xFFE7EEF3),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _openProfile,
                  customBorder: const CircleBorder(),
                  child: ProfileAvatar(
                    key: const Key('home_profile_avatar'),
                    size: avatarSize,
                    imageUrl: _profileSummary?.profileImageUrl ?? '',
                    iconSize: isTablet ? 34 : 30.sp,
                    semanticLabel: _profileSummary == null
                        ? 'Open profile'
                        : 'Open ${_profileSummary!.fullName} profile',
                  ),
                ),
              ),
            ),
            SizedBox(width: isTablet ? 16 : 12.w),
            Expanded(
              child: Text(
                key: const Key('home_welcome_text'),
                welcomeMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: TextStyle(
                  color: fbDarkPrimary,
                  fontFamily: 'Frutiger',
                  fontSize: isTablet ? 20 : 16.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            SizedBox(width: isTablet ? 16 : 12.w),
            SizedBox(
              width: avatarSize,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildTopActionButton(
                  icon: Icons.notifications_none_rounded,
                  label: _unreadCount == 0
                      ? 'Open notifications'
                      : 'Open notifications, $_unreadCount unread',
                  badge: _unreadCount,
                  onTap: _openNotifications,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isTablet ? 24 : 20.h),
        Container(
          key: const Key('home_brand_block'),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            isTablet ? 30 : 22.w,
            isTablet ? 18 : 15.h,
            isTablet ? 30 : 22.w,
            isTablet ? 20 : 17.h,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(isTablet ? 24 : 20.r),
            border: Border.all(color: const Color(0xFFD2DEE6)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFD2DEE6),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 18 : 14.w,
                    ),
                    child: Text(
                      key: const Key('home_welcome_title'),
                      'WELCOME TO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fbDarkPrimary,
                        fontFamily: 'Frutiger',
                        fontSize: isTablet ? 24 : 20.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: isTablet ? 2 : 1.6,
                        height: 1,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFD2DEE6),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isTablet ? 12 : 10.h),
              Image.asset(
                key: const Key('home_brand_logo'),
                'assets/logo/logo.png',
                width: isTablet ? 240 : 200,
                height: isTablet ? 78 : 65,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                semanticLabel: 'VerifiTOR',
              ),
            ],
          ),
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
                width: isTablet ? 52 : 48,
                height: isTablet ? 52 : 48,
                child: Icon(
                  icon,
                  size: isTablet ? 26 : 24.sp,
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
    final phoneCardHeight = 285.h < 325 ? 325.0 : 285.h;

    return Container(
      key: const Key('home_request_overview'),
      width: double.infinity,
      height: isTablet ? 330 : phoneCardHeight,
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
          padding: EdgeInsets.all(isTablet ? 28 : 22.r),
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
                        Text(
                          'My requests',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Klavika',
                            fontSize: isTablet ? 24 : 20.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: isTablet ? 22 : 16.h),
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
                              height: isTablet ? 56 : 48.h,
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
                  SizedBox(height: isTablet ? 48 : 42.h),
                  Text(
                    'Ready for your next document?',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Klavika',
                      fontSize: isTablet ? 25 : 20.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: isTablet ? 26 : 22.h),
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
                            horizontal: isTablet ? 34 : 30.w,
                            vertical: isTablet ? 15 : 14.h,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                color: const Color(0xFF2E3B0A),
                                size: isTablet ? 23 : 20.sp,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'New request',
                                style: TextStyle(
                                  color: const Color(0xFF2E3B0A),
                                  fontFamily: 'Frutiger',
                                  fontSize: isTablet ? 16 : 14.sp,
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
            fontSize: isTablet ? 17 : 13.sp,
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
                fontSize: isTablet ? 38 : 32.sp,
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
                  fontSize: isTablet ? 14 : 11.sp,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RequestListLoad {
  const _RequestListLoad({this.data, this.error});

  final List<Map<String, dynamic>>? data;
  final Object? error;
}

class _MappedRequestData {
  const _MappedRequestData({
    required this.pending,
    required this.trackingRefunds,
    required this.history,
  });

  final List<PendingRequest> pending;
  final List<HistoryItem> trackingRefunds;
  final List<HistoryItem> history;
}
