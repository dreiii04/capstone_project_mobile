import 'package:capstone_project/screens/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/custom_font.dart';
import '../screens/payment_method_screen.dart';

class PaymentDetailsScreen extends StatefulWidget {
  final PendingRequest request;

  const PaymentDetailsScreen({super.key, required this.request});

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen> {
  bool _isConfirmed = false;

  String _amountLabel(double value) => 'PHP ${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF5D7E97),
        centerTitle: true,
        title: CustomFont(text: "Payment Details", fontSize: 22.sp, color: Colors.white, fontWeight: FontWeight.bold),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Column(
          children: [
            _buildSectionCard("Billing Summary", [
              _infoRow("Document Requested", widget.request.docName),
              _infoRow(
                "Document Price",
                _amountLabel(widget.request.documentPrice),
              ),
              const Divider(),
              _infoRow(
                "Total Amount Due",
                _amountLabel(widget.request.documentPrice),
                isBold: true,
              ),
            ]),
            SizedBox(height: 15.h),
            _buildSectionCard("GCash QR", [
              Center(
                child: Image.asset(
                  'assets/image/sample_qr.png',
                  width: 200.r,
                  height: 200.r,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: 8.h),
              Center(
                child: CustomFont(
                  text:
                      "Scan to pay ${_amountLabel(widget.request.documentPrice)}",
                  fontSize: 12.sp,
                  color: Colors.black54,
                ),
              ),
            ]),
            SizedBox(height: 20.h),
            Row(
              children: [
                Checkbox(
                  value: _isConfirmed,
                  activeColor: const Color(0xFF5D7E97),
                  onChanged: (val) => setState(() => _isConfirmed = val!),
                ),
                Expanded(
                  child: CustomFont(
                    text: "I confirm that the billing details are correct and I agree to proceed to the payment page.",
                    fontSize: 11.sp, color: Colors.black54,
                  ),
                ),
              ],
            ),
            SizedBox(height: 30.h),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                onPressed: _isConfirmed 
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentMethodScreen(request: widget.request)))
                  : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF233446),
                  padding: EdgeInsets.symmetric(horizontal: 45.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
                child: CustomFont(text: "Next", color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomFont(text: title, fontSize: 16.sp, fontWeight: FontWeight.bold, color: const Color(0xFF233446)),
          SizedBox(height: 12.h),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CustomFont(text: label, fontSize: 13.sp, color: Colors.black54),
          CustomFont(text: value, fontSize: 13.sp, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: isBold ? const Color(0xFF233446) : Colors.black87),
        ],
      ),
    );
  }
}