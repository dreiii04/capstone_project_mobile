import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/request_detail_screen.dart';
import '../widgets/custom_font.dart';

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

  const PendingScreen({super.key, required this.requestList});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  static const double _maxContentWidth = 760;
  String _selectedFilter = 'All';

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
                            'Pending',
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
                                      return _buildCard(
                                        item,
                                        isTablet: isTablet,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                RequestDetailsScreen(
                                              request: item,
                                            ),
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
            color: const Color(0xFF9AA2A8),
            fontSize: isTablet ? 15 : 12,
          ),
        ),
      ],
    );

    final statusBadge = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isTablet ? 210 : 150),
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
          maxLines: 1,
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
        return const Color(0xFFE99A18);
      case 'PENDING TO COMPLETE':
        return Colors.blueGrey;
      case 'RELEASED':
        return Colors.orange;
      case 'PROCESSING':
        return Colors.green;
      case 'APPROVED':
        return Colors.blue;
      default:
        return Colors.yellow.shade700;
    }
  }

  Widget _buildEmptyState(bool isTablet) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_edu,
            size: isTablet ? 92 : 72,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: isTablet ? 20 : 14),
          CustomFont(
            text: 'No pending requests found.',
            fontSize: isTablet ? 18 : 15,
            color: Colors.grey.shade500,
          ),
        ],
      ),
    );
  }
}
