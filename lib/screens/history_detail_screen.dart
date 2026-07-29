import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'history_screen.dart';
import 'payment_refund_screen.dart';

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, required this.item});

  final HistoryItem item;

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  static const _primaryBlue = Color(0xFF5A819B);
  static const _darkNavy = Color(0xFF233446);

  HistoryItem get item => widget.item;

  String _amountLabel(double value) {
    if (value <= 0) return 'N/A';
    return 'PHP ${value.toStringAsFixed(2)}';
  }

  String _paymentMethodLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'N/A';
    if (normalized == 'receipt' || normalized == 'gcash') return 'GCash';
    if (normalized == 'onsite') return 'Other online payment';
    return value.trim();
  }

  String get _refundStatusLabel {
    final status = item.refundStatus.trim();
    if (status.isEmpty) return '';
    return status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _openRefundScreen() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PaymentRefundScreen(item: item)),
    );
    if (submitted == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Request details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 32.0 : 16.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCard(
                        title: 'Request information',
                        icon: Icons.description_outlined,
                        children: [
                          _row('Document', item.title),
                          _row('Purpose', item.purpose),
                          _row(
                            'Date requested',
                            DateFormat('MMM d, y').format(item.date),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildStatusCard(),
                      const SizedBox(height: 16),
                      _buildCard(
                        title: 'Payment summary',
                        icon: Icons.payments_outlined,
                        children: [
                          _row('Amount paid', _amountLabel(item.totalAmount)),
                          _row(
                            'Payment method',
                            _paymentMethodLabel(item.paymentType),
                          ),
                          _row(
                            'Date paid',
                            DateFormat('MMM d, y').format(item.date),
                          ),
                        ],
                      ),
                      if (item.hasRefundRequest) ...[
                        const SizedBox(height: 16),
                        _buildRefundStatusCard(),
                      ] else if (item.canRequestRefund) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            key: const Key('request_refund_button'),
                            onPressed: _openRefundScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _darkNavy,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.currency_exchange_rounded),
                            label: const Text(
                              'Request refund',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Available because this rejected request has a received payment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF687680),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor =
        item.isApproved ? const Color(0xFF218739) : const Color(0xFFB42318);
    final message = item.isApproved
        ? "This document has been processed and released by the Registrar's Office."
        : item.hasRefundRequest
            ? 'This request was rejected and your refund request is being reviewed.'
            : item.canRequestRefund
                ? 'This request was rejected after payment was received. You can request a refund below.'
                : 'This request was rejected. Please contact the office for more details.';

    return _buildCard(
      title: 'Final status',
      icon: item.isApproved
          ? Icons.check_circle_outline_rounded
          : Icons.cancel_outlined,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(24),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.isApproved ? Icons.check_circle : Icons.cancel,
                color: statusColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  item.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            color: Color(0xFF687680),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildRefundStatusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE09A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFF9A6700)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refund $_refundStatusLabel',
                  style: const TextStyle(
                    color: Color(0xFF694A00),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'The office is reviewing your refund. You will receive a notification when its status changes.',
                  style: TextStyle(
                    color: Color(0xFF765B1B),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _darkNavy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF687680),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.isEmpty ? 'N/A' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _darkNavy,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
