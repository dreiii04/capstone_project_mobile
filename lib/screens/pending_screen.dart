import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/request_detail_screen.dart';

class PendingRequest {
  final String docName;
  final String purpose;
  final DateTime dateCreated;
  final String status;
  final double documentPrice;
  final double totalAmount;

  PendingRequest({
    required this.docName,
    required this.purpose,
    required this.dateCreated,
    required this.status,
    this.documentPrice = 0,
    double? totalAmount,
  }) : totalAmount = totalAmount ?? documentPrice;
}

class PendingScreen extends StatefulWidget {
  final List<PendingRequest> requestList;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function()? onRefresh;

  const PendingScreen({
    super.key,
    required this.requestList,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
  });

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  static const double _maxContentWidth = 760;
  static const Color _primaryBlue = Color(0xFF5D7E97);
  String _selectedFilter = 'All';

  bool get _hasError => widget.errorMessage?.trim().isNotEmpty == true;

  @override
  void didUpdateWidget(covariant PendingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedFilter != 'All' &&
        !widget.requestList
            .any((request) => request.docName == _selectedFilter)) {
      _selectedFilter = 'All';
    }
  }

  Future<void> _refresh() async {
    final callback = widget.onRefresh;
    if (callback != null) await callback();
  }

  Future<void> _openDetails(PendingRequest item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => RequestDetailsScreen(request: item),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final filters = <String>[
      'All',
      ...widget.requestList.map((request) => request.docName).toSet(),
    ];
    final filteredList = _selectedFilter == 'All'
        ? widget.requestList
        : widget.requestList
            .where((request) => request.docName == _selectedFilter)
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
                                  'Pending',
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
                            key: const Key('pending_filter'),
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
                          if (_hasError && widget.requestList.isNotEmpty) ...[
                            SizedBox(height: isTablet ? 14 : 10),
                            _buildErrorBanner(isTablet),
                          ],
                          if (widget.isLoading &&
                              widget.requestList.isNotEmpty) ...[
                            SizedBox(height: isTablet ? 14 : 10),
                            const LinearProgressIndicator(
                              key: Key('pending_refresh_progress'),
                              color: _primaryBlue,
                              backgroundColor: Color(0xFFDDE7ED),
                            ),
                          ],
                          SizedBox(height: isTablet ? 20 : 14),
                          Expanded(
                            child: RefreshIndicator(
                              key: const Key('pending_refresh_indicator'),
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
      key: const Key('pending_refresh_button'),
      tooltip: 'Refresh pending requests',
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

  Widget _buildBody(List<PendingRequest> filteredList, bool isTablet) {
    if (widget.isLoading && widget.requestList.isEmpty) {
      return _buildScrollableState(
        key: const Key('pending_loading_state'),
        icon: const SizedBox.square(
          dimension: 42,
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
        title: 'Loading pending requests…',
        message: 'Please wait while we get the latest request updates.',
        isTablet: isTablet,
      );
    }

    if (_hasError && widget.requestList.isEmpty) {
      return _buildScrollableState(
        key: const Key('pending_error_state'),
        icon: Icon(
          Icons.cloud_off_rounded,
          size: isTablet ? 82 : 66,
          color: const Color(0xFF8A98A3),
        ),
        title: 'Pending requests could not be loaded',
        message: widget.errorMessage!.trim(),
        isTablet: isTablet,
        action: _buildRetryButton('Try again'),
      );
    }

    if (filteredList.isEmpty) {
      final filtered = widget.requestList.isNotEmpty;
      return _buildScrollableState(
        key: const Key('pending_empty_state'),
        icon: Icon(
          filtered
              ? Icons.filter_alt_off_rounded
              : Icons.pending_actions_rounded,
          size: isTablet ? 88 : 70,
          color: const Color(0xFFB5C1C8),
        ),
        title:
            filtered ? 'No requests match this filter' : 'No pending requests',
        message: filtered
            ? 'Choose All or another document type to see your requests.'
            : 'New and in-progress document requests will appear here.',
        isTablet: isTablet,
        action: filtered
            ? OutlinedButton(
                key: const Key('pending_clear_filter_button'),
                onPressed: () => setState(() => _selectedFilter = 'All'),
                child: const Text('Show all requests'),
              )
            : _buildRetryButton('Refresh'),
      );
    }

    return ListView.separated(
      key: const Key('pending_request_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: isTablet ? 32 : 22),
      itemCount: filteredList.length,
      separatorBuilder: (_, __) => SizedBox(height: isTablet ? 16 : 12),
      itemBuilder: (context, index) {
        final item = filteredList[index];
        return _buildCard(
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
        'pending_state_${label.toLowerCase().replaceAll(' ', '_')}_button',
      ),
      onPressed: widget.isLoading ? null : _refresh,
      style: FilledButton.styleFrom(backgroundColor: _primaryBlue),
      icon: const Icon(Icons.refresh_rounded),
      label: Text(label),
    );
  }

  Widget _buildErrorBanner(bool isTablet) {
    return Container(
      key: const Key('pending_error_banner'),
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

  Widget _buildCard(
    PendingRequest item, {
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    final statusColor = _getStatusColor(item.status);
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.docName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF252A2E),
            fontSize: isTablet ? 19 : 16,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: isTablet ? 10 : 8),
        Text(
          DateFormat('MMM d, y  h:mm a').format(item.dateCreated),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF7B878F),
            fontSize: isTablet ? 15 : 12,
          ),
        ),
      ],
    );

    final statusBadge = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isTablet ? 210 : 170),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 14 : 10,
          vertical: isTablet ? 8 : 6,
        ),
        decoration: BoxDecoration(
          color: statusColor.withAlpha(40),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          item.status,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: statusColor,
            fontSize: isTablet ? 12 : 10,
            fontWeight: FontWeight.w700,
          ),
        ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, card) {
              if (card.maxWidth < 340) {
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
                crossAxisAlignment: CrossAxisAlignment.center,
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

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING FOR PAYMENT':
        return const Color(0xFFC67500);
      case 'PENDING TO COMPLETE':
        return Colors.blueGrey;
      case 'RELEASED':
        return Colors.orange;
      case 'PROCESSING':
        return const Color(0xFF218739);
      case 'APPROVED':
        return const Color(0xFF246BCE);
      default:
        return const Color(0xFF8A6D00);
    }
  }
}
