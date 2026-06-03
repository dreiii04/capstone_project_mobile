import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../screens/history_screen.dart';

class HistoryDetailScreen extends StatelessWidget {
  final HistoryItem item;
  const HistoryDetailScreen({super.key, required this.item});

  String _amountLabel(double value) {
    if (value <= 0) return 'N/A';
    return 'PHP ${value.toStringAsFixed(2)}';
  }

  String _paymentMethodLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'N/A';
    if (normalized == 'receipt' || normalized == 'gcash') return 'GCash';
    if (normalized == 'onsite') return 'Other Online Payment';
    return value.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF5D7E97),
        title: const Text("History Details", style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          children: [
            _buildCard("Request Information", [
              _row("Document:", item.title),
              _row("Purpose:", item.purpose),
              _row("Date Requested:", DateFormat('MMM d, y').format(item.date)),
            ]),
            SizedBox(height: 15.h),
            _buildCard("Final Status", [
              Row(
                children: [
                  Icon(item.isApproved ? Icons.check_circle : Icons.cancel, 
                       color: item.isApproved ? Colors.green : Colors.red),
                  SizedBox(width: 10.w),
                  Text(item.status, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
                ],
              ),
              SizedBox(height: 10.h),
              Text(item.isApproved 
                ? "This document has been processed and released by the Registrar's Office."
                : "This request was rejected. Please contact the office for more details.",
                style: TextStyle(fontSize: 12.sp, color: Colors.black54),
              ),
            ]),
            SizedBox(height: 15.h),
            _buildCard("Payment Summary", [
              _row("Amount Paid:", _amountLabel(item.totalAmount)),
              _row("Payment Method:", _paymentMethodLabel(item.paymentType)),
              _row("Date Paid:", DateFormat('MMM d, y').format(item.date)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
        const Divider(),
        ...children,
      ]),
    );
  }

  Widget _row(String label, String val) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
        Text(val, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}