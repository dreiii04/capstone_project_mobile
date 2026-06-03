import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../widgets/custom_font.dart';
import '../screens/history_detail_screen.dart';


class HistoryItem {
  final String title;
  final DateTime date;
  final String purpose; // New
  final String status;  // e.g., "Released", "Rejected"
  final bool isApproved;
  final double totalAmount;
  final String paymentType;

  HistoryItem({
    required this.title, 
    required this.date, 
    required this.purpose,
    required this.status,
    required this.isApproved,
    required this.totalAmount,
    required this.paymentType,
  });
}

class HistoryScreen extends StatefulWidget {
  final List<HistoryItem> historyList;
  const HistoryScreen({super.key, required this.historyList});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = "All";

  @override
  Widget build(BuildContext context) {
    // Filter Logic
    List<String> filters = ["All"];
    filters.addAll(widget.historyList.map((e) => e.title).toSet().toList());

    List<HistoryItem> filteredList = _selectedFilter == "All"
        ? widget.historyList
        : widget.historyList.where((h) => h.title == _selectedFilter).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Container(height: 70.h, width: double.infinity, color: const Color(0xFF5D7E97)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20.h),
                  CustomFont(text: "History", fontSize: 40.sp, fontWeight: FontWeight.bold, color: Colors.black),
                  
                  // Filter Dropdown
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 10.h),
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedFilter,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: filters.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      onChanged: (val) => setState(() => _selectedFilter = val!),
                    ),
                  ),

                  Expanded(
                    child: filteredList.isNotEmpty
                        ? ListView.builder(
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final item = filteredList[index];
                              return InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => HistoryDetailScreen(item: item)),
                                ),
                                child: _buildHistoryCard(item),
                              );
                            },
                          )
                        : const Center(child: Text("No history found")),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(HistoryItem item) {
    return Container(
      margin: EdgeInsets.only(bottom: 15.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomFont(text: item.title, fontSize: 18.sp, fontWeight: FontWeight.bold, color: const Color(0xFF233446)),
          CustomFont(text: DateFormat('MMMM d, y').format(item.date), fontSize: 13.sp, color: Colors.black54),
          SizedBox(height: 15.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F5),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.isApproved ? Icons.check_circle : Icons.cancel, 
                     size: 14.sp, color: item.isApproved ? Colors.green : Colors.red),
                SizedBox(width: 8.w),
                CustomFont(text: item.status, fontSize: 12.sp, fontWeight: FontWeight.w600, color: item.isApproved ? Colors.green : Colors.red),
              ],
            ),
          )
        ],
      ),
    );
  }
}