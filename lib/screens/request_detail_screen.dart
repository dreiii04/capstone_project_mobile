import 'package:capstone_project/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../widgets/custom_font.dart';
import '../screens/payment_details_screen.dart';
import '../screens/pending_screen.dart';

class RequestDetailsScreen extends StatelessWidget {
  final PendingRequest request;
  const RequestDetailsScreen({super.key, required this.request});

  String _amountLabel(double value) => 'PHP ${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final request = this.request;
    final statusUpper = request.status.toUpperCase();
    final needsPayment = statusUpper == 'PENDING FOR PAYMENT';
    final pendingCompletion = statusUpper == 'PENDING TO COMPLETE';
    final statusNote = needsPayment
        ? "Payment is required to continue processing your request. Please complete your payment to proceed."
        : pendingCompletion
            ? "Payment received. Your request is pending completion."
            : "Your request is being processed.";
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF5D7E97),
        title: const Text(
          "Information of the Request",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: fbTextColorWhite),
        ),
        leading: IconButton(
          key: const Key('request_detail_back_button'),
          tooltip: 'Back to requests',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          children: [
            _buildSectionCard("Document Details", [
              _buildInfoRow("Type of Document:", request.docName),
              _buildInfoRow("Purpose of Request:", request.purpose),
              _buildInfoRow("Date Requested:",
                  DateFormat('MMMM d, y').format(request.dateCreated)),
            ]),
            SizedBox(height: 15.h),
            _buildSectionCard("Request Status", [
              _buildInfoRow(
                  "Date:", DateFormat('MMMM d, y').format(request.dateCreated)),
              _buildInfoRow(
                  "Time:", DateFormat('h:mm a').format(request.dateCreated)),
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(5.r)),
                child: Text(request.status,
                    style: TextStyle(
                        color: Colors.yellow.shade800,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(height: 10.h),
              Text(
                statusNote,
                style: TextStyle(
                  color: needsPayment ? Colors.red : Colors.black54,
                  fontSize: 11,
                ),
              ),
            ]),
            SizedBox(height: 15.h),
            _buildSectionCard("Payment Summary", [
              _buildInfoRow(
                "Document Price:",
                _amountLabel(request.documentPrice),
              ),
              const Divider(),
              _buildInfoRow(
                "Total Amount Due:",
                _amountLabel(request.documentPrice),
                isBold: true,
              ),
              SizedBox(height: 15.h),
              if (needsPayment)
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PaymentDetailsScreen(request: request),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF233446)),
                    child: CustomFont(
                        text: "Pay now",
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(15.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
          const Divider(),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.sp, color: Colors.black54),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
