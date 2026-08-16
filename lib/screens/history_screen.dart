import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/history_detail_screen.dart';

class HistoryItem {
  final String requestId;
  final String transactionId;
  final String title;
  final DateTime date;
  final String purpose;
  final String status;
  final bool isApproved;
  final double totalAmount;
  final String paymentType;
  final String remarks;
  String refundStatus;

  HistoryItem({
    this.requestId = '',
    this.transactionId = '',
    required this.title,
    required this.date,
    required this.purpose,
    required this.status,
    required this.isApproved,
    required this.totalAmount,
    required this.paymentType,
    this.remarks = '',
    this.refundStatus = '',
  });

  bool get isRejected {
    final normalized = status.trim().toLowerCase();
    return normalized == 'rejected' ||
        normalized == 'declined' ||
        normalized == 'denied';
  }

  bool _isPlaceholder(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return const {'none', 'null', 'n/a', 'na', '_', 'not_applicable'}
        .contains(normalized);
  }

  String get displayRemarks {
    final value = remarks.trim();
    return !hasRemarks
        ? "No remarks were supplied by the Registrar's Office."
        : value;
  }

  bool get hasRemarks {
    final value = remarks.trim();
    return value.isNotEmpty && !_isPlaceholder(value);
  }

  bool get canRequestRefund {
    return isRejected &&
        totalAmount > 0 &&
        paymentType.trim().isNotEmpty &&
        transactionId.trim().isNotEmpty &&
        !hasRefundRequest;
  }

  bool get hasRefundRequest {
    final value = refundStatus.trim();
    return value.isNotEmpty && !_isPlaceholder(value);
  }
}

class HistoryScreen extends StatefulWidget {
  final List<HistoryItem> historyList;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function()? onRefresh;

  const HistoryScreen({
    super.key,
    required this.historyList,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const double _maxContentWidth = 760;
  static const Color _primaryBlue = Color(0xFF5D7E97);
  String _selectedFilter = 'All';

  bool get _hasError => widget.errorMessage?.trim().isNotEmpty == true;

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedFilter != 'All' &&
        !widget.historyList.any((item) => item.title == _selectedFilter)) {
      _selectedFilter = 'All';
    }
  }

  Future<void> _refresh() async {
    final callback = widget.onRefresh;
    if (callback != null) await callback();
  }

  Future<void> _openDetails(HistoryItem item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (context) => HistoryDetailScreen(item: item)),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final filters = <String>[
      'All',
      ...widget.historyList.map((item) => item.title).toSet(),
    ];
    final filteredList = _selectedFilter == 'All'
        ? widget.historyList
        : widget.historyList
            .where((item) => item.title == _selectedFilter)
            .toList();

    return LayoutBuilder(
      builder: (context, viewport) {
        final isTablet = viewport.maxWidth >= 600;
        final horizontalPadding = isTablet ? 32.0 : 14.0;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: _primaryBlue,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(height: isTablet ? 48 : 40),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _maxContentWidth),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: isTablet ? 26 : 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'History',
                                  style: TextStyle(
                                    color: const Color(0xFF1F252A),
                                    fontSize: isTablet ? 36 : 30,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _buildRefreshButton(isTablet),
                            ],
                          ),
                          SizedBox(height: isTablet ? 18 : 12),
                          DropdownButtonFormField<String>(
                            key: const Key('history_filter'),
                            initialValue: _selectedFilter,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            decoration: InputDecoration(
                              labelText: 'Filter by document',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 20 : 15,
                                vertical: isTablet ? 17 : 13,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE0E4E7),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF5A819B),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            items: filters
                                .map(
                                  (value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: isTablet ? 17 : 15,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _selectedFilter = value);
                            },
                          ),
                          if (_hasError && widget.historyList.isNotEmpty) ...[
                            SizedBox(height: isTablet ? 14 : 10),
                            _buildErrorBanner(isTablet),
                          ],
                          if (widget.isLoading &&
                              widget.historyList.isNotEmpty) ...[
                            SizedBox(height: isTablet ? 14 : 10),
                            const LinearProgressIndicator(
                              key: Key('history_refresh_progress'),
                              color: _primaryBlue,
                              backgroundColor: Color(0xFFDDE7ED),
                            ),
                          ],
                          SizedBox(height: isTablet ? 20 : 14),
                          Expanded(
                            child: RefreshIndicator(
                              key: const Key('history_refresh_indicator'),
                              color: _primaryBlue,
                              onRefresh: _refresh,
                              child: _buildBody(filteredList, isTablet),
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
        );
      },
    );
  }

  Widget _buildRefreshButton(bool isTablet) {
    return IconButton(
      key: const Key('history_refresh_button'),
      tooltip: 'Refresh request history',
      onPressed: widget.onRefresh == null || widget.isLoading ? null : _refresh,
      style: IconButton.styleFrom(
        minimumSize: Size.square(isTablet ? 50 : 44),
        backgroundColor: const Color(0xFFE3EDF3),
        foregroundColor: _primaryBlue,
      ),
      icon: widget.isLoading
          ? SizedBox.square(
              dimension: isTablet ? 22 : 19,
              child: const CircularProgressIndicator(strokeWidth: 2.3),
            )
          : const Icon(Icons.refresh_rounded),
    );
  }

  Widget _buildBody(List<HistoryItem> filteredList, bool isTablet) {
    if (widget.isLoading && widget.historyList.isEmpty) {
      return _buildScrollableState(
        key: const Key('history_loading_state'),
        icon: const SizedBox.square(
          dimension: 42,
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
        title: 'Loading request history…',
        message: 'Please wait while we get your completed request records.',
        isTablet: isTablet,
      );
    }

    if (_hasError && widget.historyList.isEmpty) {
      return _buildScrollableState(
        key: const Key('history_error_state'),
        icon: Icon(
          Icons.cloud_off_rounded,
          size: isTablet ? 82 : 66,
          color: const Color(0xFF8A98A3),
        ),
        title: 'Request history could not be loaded',
        message: widget.errorMessage!.trim(),
        isTablet: isTablet,
        action: _buildRetryButton('Try again'),
      );
    }

    if (filteredList.isEmpty) {
      final filtered = widget.historyList.isNotEmpty;
      return _buildScrollableState(
        key: const Key('history_empty_state'),
        icon: Icon(
          filtered ? Icons.filter_alt_off_rounded : Icons.history_edu_rounded,
          size: isTablet ? 88 : 70,
          color: const Color(0xFFB5C1C8),
        ),
        title: filtered
            ? 'No history matches this filter'
            : 'No request history yet',
        message: filtered
            ? 'Choose All or another document type to see your records.'
            : 'Completed and rejected requests will appear here.',
        isTablet: isTablet,
        action: filtered
            ? OutlinedButton(
                key: const Key('history_clear_filter_button'),
                onPressed: () => setState(() => _selectedFilter = 'All'),
                child: const Text('Show all history'),
              )
            : _buildRetryButton('Refresh'),
      );
    }

    return ListView.separated(
      key: const Key('history_request_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: isTablet ? 32 : 22),
      itemCount: filteredList.length,
      separatorBuilder: (_, __) => SizedBox(height: isTablet ? 16 : 12),
      itemBuilder: (context, index) {
        final item = filteredList[index];
        return _buildHistoryCard(
          item,
          isTablet: isTablet,
          onTap: () => _openDetails(item),
        );
      },
    );
  }

  Widget _buildScrollableState({
    required Key key,
    required Widget icon,
    required String title,
    required String message,
    required bool isTablet,
    Widget? action,
  }) {
    return CustomScrollView(
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  SizedBox(height: isTablet ? 20 : 15),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF33434E),
                      fontSize: isTablet ? 20 : 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF788791),
                      fontSize: isTablet ? 15 : 13,
                      height: 1.4,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: 18),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildRetryButton(String label) {
    if (widget.onRefresh == null) return null;
    return FilledButton.icon(
      key: Key(
        'history_state_${label.toLowerCase().replaceAll(' ', '_')}_button',
      ),
      onPressed: widget.isLoading ? null : _refresh,
      style: FilledButton.styleFrom(backgroundColor: _primaryBlue),
      icon: const Icon(Icons.refresh_rounded),
      label: Text(label),
    );
  }

  Widget _buildErrorBanner(bool isTablet) {
    return Container(
      key: const Key('history_error_banner'),
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 14 : 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD2CC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.errorMessage!.trim(),
              style: TextStyle(
                color: const Color(0xFF7A271A),
                fontSize: isTablet ? 14 : 12,
                height: 1.35,
              ),
            ),
          ),
          if (widget.onRefresh != null)
            IconButton(
              tooltip: 'Try again',
              onPressed: widget.isLoading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              color: const Color(0xFFB42318),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    HistoryItem item, {
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    final statusColor =
        item.isApproved ? const Color(0xFF218739) : const Color(0xFFB42318);
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF233446),
            fontSize: isTablet ? 19 : 16,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: isTablet ? 9 : 7),
        Text(
          DateFormat('MMMM d, y').format(item.date),
          style: TextStyle(
            color: const Color(0xFF687680),
            fontSize: isTablet ? 15 : 12,
          ),
        ),
        if (item.isRejected) ...[
          SizedBox(height: isTablet ? 12 : 9),
          _buildRemarksPreview(item, isTablet),
        ],
        if (item.canRequestRefund || item.hasRefundRequest) ...[
          SizedBox(height: isTablet ? 10 : 8),
          Row(
            children: [
              Icon(
                item.hasRefundRequest
                    ? Icons.schedule_rounded
                    : Icons.currency_exchange_rounded,
                size: isTablet ? 17 : 14,
                color: _primaryBlue,
              ),
              SizedBox(width: isTablet ? 7 : 5),
              Expanded(
                child: Text(
                  item.hasRefundRequest
                      ? 'Refund ${_readableStatus(item.refundStatus)}'
                      : 'Refund available',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryBlue,
                    fontSize: isTablet ? 13 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    final statusBadge = Container(
      constraints: BoxConstraints(maxWidth: isTablet ? 210 : 170),
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 14 : 10,
        vertical: isTablet ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(24),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.isApproved ? Icons.check_circle : Icons.cancel,
            size: isTablet ? 18 : 14,
            color: statusColor,
          ),
          SizedBox(width: isTablet ? 8 : 5),
          Flexible(
            child: Text(
              item.status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor,
                fontSize: isTablet ? 13 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isTablet ? 16 : 13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24 : 16,
            vertical: isTablet ? 22 : 17,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isTablet ? 16 : 13),
            border: Border.all(color: const Color(0xFFEDF0F2)),
          ),
          child: LayoutBuilder(
            builder: (context, card) {
              if (card.maxWidth < 370) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    information,
                    const SizedBox(height: 13),
                    statusBadge,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: information),
                  SizedBox(width: isTablet ? 24 : 12),
                  Flexible(child: statusBadge),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRemarksPreview(HistoryItem item, bool isTablet) {
    return Container(
      key: const Key('history_remarks_preview'),
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 12 : 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD7D1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remarks',
            style: TextStyle(
              color: const Color(0xFF9A2318),
              fontSize: isTablet ? 13 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.displayRemarks,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF73413C),
              fontSize: isTablet ? 13 : 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _readableStatus(String value) {
    final words = value
        .trim()
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'updated';
    return words
        .map((word) =>
            '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}
