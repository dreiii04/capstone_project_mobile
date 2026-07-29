import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/history_detail_screen.dart';
import '../widgets/custom_font.dart';

class HistoryItem {
  final String transactionId;
  final String title;
  final DateTime date;
  final String purpose;
  final String status;
  final bool isApproved;
  final double totalAmount;
  final String paymentType;
  String refundStatus;

  HistoryItem({
    this.transactionId = '',
    required this.title,
    required this.date,
    required this.purpose,
    required this.status,
    required this.isApproved,
    required this.totalAmount,
    required this.paymentType,
    this.refundStatus = '',
  });

  bool get canRequestRefund {
    return status.trim().toLowerCase() == 'rejected' &&
        totalAmount > 0 &&
        paymentType.trim().isNotEmpty &&
        transactionId.trim().isNotEmpty &&
        refundStatus.trim().isEmpty;
  }

  bool get hasRefundRequest => refundStatus.trim().isNotEmpty;
}

class HistoryScreen extends StatefulWidget {
  final List<HistoryItem> historyList;

  const HistoryScreen({super.key, required this.historyList});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const double _maxContentWidth = 760;
  String _selectedFilter = 'All';

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
                height: isTablet ? 72 : 64,
                width: double.infinity,
                color: const Color(0xFF5D7E97),
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
                          Text(
                            'History',
                            style: TextStyle(
                              color: const Color(0xFF1F252A),
                              fontSize: isTablet ? 36 : 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: isTablet ? 18 : 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedFilter,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            decoration: InputDecoration(
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
                          SizedBox(height: isTablet ? 20 : 14),
                          Expanded(
                            child: filteredList.isEmpty
                                ? _buildEmptyState(isTablet)
                                : ListView.separated(
                                    padding: EdgeInsets.only(
                                      bottom: isTablet ? 32 : 22,
                                    ),
                                    itemCount: filteredList.length,
                                    separatorBuilder: (_, __) => SizedBox(
                                      height: isTablet ? 16 : 12,
                                    ),
                                    itemBuilder: (context, index) {
                                      final item = filteredList[index];
                                      return _buildHistoryCard(
                                        item,
                                        isTablet: isTablet,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                HistoryDetailScreen(item: item),
                                          ),
                                        ),
                                      );
                                    },
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

  Widget _buildHistoryCard(
    HistoryItem item, {
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    final statusColor = item.isApproved ? Colors.green : Colors.red;

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        color: Colors.black54,
                        fontSize: isTablet ? 15 : 12,
                      ),
                    ),
                    if (item.canRequestRefund || item.hasRefundRequest) ...[
                      SizedBox(height: isTablet ? 9 : 7),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.hasRefundRequest
                                ? Icons.schedule_rounded
                                : Icons.currency_exchange_rounded,
                            size: isTablet ? 17 : 14,
                            color: const Color(0xFF5A819B),
                          ),
                          SizedBox(width: isTablet ? 7 : 5),
                          Text(
                            item.hasRefundRequest
                                ? 'Refund ${item.refundStatus.toLowerCase()}'
                                : 'Refund available',
                            style: TextStyle(
                              color: const Color(0xFF5A819B),
                              fontSize: isTablet ? 13 : 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: isTablet ? 24 : 12),
              Flexible(
                child: Container(
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
                          maxLines: 1,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isTablet) {
    return Center(
      child: CustomFont(
        text: 'No history found.',
        fontSize: isTablet ? 18 : 15,
        color: Colors.grey.shade500,
      ),
    );
  }
}
