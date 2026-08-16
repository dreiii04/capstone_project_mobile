import 'package:capstone_project/screens/home_screen.dart';
import 'package:capstone_project/screens/pending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../widgets/custom_font.dart';
import '../services/mongo_data_api_service.dart';
import '../widgets/simple_message_dialog.dart';
import '../widgets/request_progress_indicator.dart';

class RequestFormScreen extends StatefulWidget {
  const RequestFormScreen({super.key});

  @override
  State<RequestFormScreen> createState() => _RequestFormScreenState();
}

class _RequestFormScreenState extends State<RequestFormScreen> {
  // --- State Variables ---
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  String? _mainDocType;
  String? _selectedPurpose;
  bool _isConfirmed = false;
  bool _isSubmitting = false;

  final TextEditingController _otherDocumentController =
      TextEditingController();
  final TextEditingController _otherPurposeController = TextEditingController();

  // --- Document Price Data ---
  final List<Map<String, dynamic>> allDocuments = [
    {'name': 'F-137 (SH)', 'price': 400.00},
    {'name': 'F-137 (GS/JH)', 'price': 250.00},
    {'name': 'Transcript of Records (TOR)', 'price': 600.00},
    {'name': 'General Weighted Average (GWA)', 'price': 250.00},
    {'name': 'Good Moral Character/ESC (GMC/ESC)', 'price': 200.00},
    {'name': 'Card (re-print)', 'price': 200.00},
    {'name': 'MOI (Memorandum of Inclusion)', 'price': 250.00},
    {'name': 'Student Verification', 'price': 250.00},
    {'name': 'Request Form (Lost)', 'price': 200.00},
    {'name': 'Certified True Copy (CTC)', 'price': 200.00},
    {'name': 'Diploma (2nd Copy)', 'price': 300.00},
    {'name': 'Application for Graduation', 'price': 200.00},
    {'name': 'Prospectus', 'price': 200.00},
    {'name': 'Certificate of Grades', 'price': 250.00},
    {'name': 'Transfer Credential', 'price': 300.00},
    {'name': 'Certificate of Enrollment', 'price': 250.00},
    {'name': 'Clearance', 'price': 200.00},
    {'name': 'Others', 'price': 0.00},
  ];

  final List<String> purposes = [
    'Employment',
    'Board Exam',
    'Personal Use',
    'Transfer',
    'Others'
  ];

  // --- Logic Methods ---

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: Text("Notice",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp)),
        content: Text(message, style: TextStyle(fontSize: 14.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK",
                style: TextStyle(
                    color: Color(0xFF233446), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  double _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String? _validateOtherInput(String? value, String fieldName) {
    final trimmed = value?.trim() ?? '';
    final wordCount = trimmed.isEmpty
        ? 0
        : trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

    if (trimmed.isEmpty) {
      return 'Please specify $fieldName.';
    }

    if (trimmed.length < 3 && wordCount < 2) {
      return 'Please enter at least 3 characters or 2 words.';
    }

    return null;
  }

  Future<void> _handleSubmission() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Check Checkbox
    if (!_isConfirmed) {
      _showErrorDialog(
          "Please confirm that your details are accurate by checking the box.");
      return;
    }

    // Prepare data for the Pending Screen
    String finalDocName = (_mainDocType == 'Others')
        ? _otherDocumentController.text.trim()
        : _mainDocType!;

    String finalPurpose = (_selectedPurpose == 'Others')
        ? _otherPurposeController.text.trim()
        : _selectedPurpose!;

    setState(() {
      _isSubmitting = true;
    });

    Map<String, dynamic>? response;
    try {
      response = await MongoDataApiService.instance.createDocumentRequest(
        docName: finalDocName,
        purpose: finalPurpose,
      );
    } catch (e) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        title: 'Request failed',
      );
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });

    // Redirect to Pending Screen (Index 1 of your Home/Main layout)
    // Adjust 'HomeScreen' to match your actual Main/Home class name
    final requestData = response['request'];
    final requestMap = requestData is Map
        ? Map<String, dynamic>.from(requestData)
        : <String, dynamic>{};
    final statusRaw = requestMap['status']?.toString() ?? '';
    final documentPrice = _parseAmount(requestMap['documentPrice']);
    final totalAmount = _parseAmount(requestMap['totalAmount']);
    final resolvedTotal = totalAmount > 0 ? totalAmount : documentPrice;
    final displayStatus = statusRaw.trim().toLowerCase() == 'pending_completion'
        ? 'PENDING TO COMPLETE'
        : 'PENDING FOR PAYMENT';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SuccessfulScreen(
          request: PendingRequest(
            status: displayStatus,
            purpose: finalPurpose,
            docName: finalDocName,
            dateCreated: DateTime.now(),
            documentPrice: documentPrice,
            totalAmount: resolvedTotal,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _otherDocumentController.dispose();
    _otherPurposeController.dispose();
    super.dispose();
  }

  // --- UI Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light grey background
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('request_form_back_button'),
          tooltip: 'Back to data consent',
          onPressed: _isSubmitting ? null : () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF233446),
          ),
        ),
        title: Image.asset(
          'assets/logo/logo.png',
          width: 92.w,
          height: 30.h,
          fit: BoxFit.contain,
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isSubmitting
                    ? const Color(0xFFAAB3B9)
                    : const Color(0xFF356A94),
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 6.w),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(47.h),
          child: RequestProgressIndicator(
            currentStep: _isSubmitting ? 2 : 1,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(25.w),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Document Request",
                  style:
                      TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 20.h),

              // Document Price List
              Text("Available Documents and Prices",
                  style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              SizedBox(height: 12.h),
              _buildPriceListTable(),
              SizedBox(height: 30.h),

              // Document Dropdown
              _buildLabel("Document:"),
              _buildDropdown(
                hint: "Choose Document",
                value: _mainDocType,
                items:
                    allDocuments.map((doc) => doc['name'].toString()).toList(),
                onChanged: (val) => setState(() => _mainDocType = val),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please select a document.';
                  }
                  return null;
                },
              ),

              if (_mainDocType == 'Others') ...[
                SizedBox(height: 10.h),
                TextFormField(
                  controller: _otherDocumentController,
                  decoration: _inputDecoration(hint: "Please specify document"),
                  validator: (value) =>
                      _validateOtherInput(value, 'the document'),
                ),
              ],

              // 3. Purpose Dropdown
              _buildLabel("Purpose of Request:"),
              _buildDropdown(
                hint: "Purpose of Request",
                value: _selectedPurpose,
                items: purposes,
                onChanged: (val) => setState(() => _selectedPurpose = val),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please select a purpose.';
                  }
                  return null;
                },
              ),

              // 4. Conditional Other Field
              if (_selectedPurpose == 'Others') ...[
                SizedBox(height: 10.h),
                TextFormField(
                  controller: _otherPurposeController,
                  decoration: _inputDecoration(hint: "Please specify purpose"),
                  validator: (value) =>
                      _validateOtherInput(value, 'the purpose'),
                ),
              ],

              SizedBox(height: 120.h), // Spacing before footer

              // 5. Checkbox
              Row(
                children: [
                  Checkbox(
                    value: _isConfirmed,
                    activeColor: const Color(0xFF5D7E97),
                    onChanged: (val) => setState(() => _isConfirmed = val!),
                  ),
                  Expanded(
                    child: Text(
                      "I confirm that the details I provided are true, accurate, and complete.",
                      style: TextStyle(fontSize: 11.sp, color: Colors.black54),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20.h),

              // 6. Submit Button
              Align(
                alignment: Alignment.bottomRight,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF233446), // Dark Navy
                    padding:
                        EdgeInsets.symmetric(horizontal: 45.w, vertical: 12.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r)),
                  ),
                  child: Text(_isSubmitting ? "Submitting..." : "Submit",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildLabel(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, top: 15.h),
      child: Text(text,
          style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.black87)),
    );
  }

  Widget _buildDropdown(
      {required String hint,
      String? value,
      required List<String> items,
      required Function(String?) onChanged,
      String? Function(String?)? validator}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 5,
              offset: const Offset(0, 2))
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        hint: Text(hint, style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 15.w),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.r),
              borderSide: BorderSide.none),
        ),
        validator: validator,
        items: items
            .map((e) => DropdownMenuItem(
                value: e, child: Text(e, style: TextStyle(fontSize: 13.sp))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.sp, color: Colors.grey),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 15.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget _buildPriceListTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 5,
              offset: const Offset(0, 2))
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF5D7E97)),
          headingTextStyle: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12.sp),
          dataRowMinHeight: 40.h,
          dataRowMaxHeight: 40.h,
          columnSpacing: 20.w,
          columns: [
            DataColumn(
              label: Text('Document', style: TextStyle(fontSize: 12.sp)),
            ),
            DataColumn(
              label: Text('Price (₱)', style: TextStyle(fontSize: 12.sp)),
            ),
          ],
          rows: allDocuments
              .map((doc) => DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 200.w,
                          child: Text(
                            doc['name'],
                            style: TextStyle(
                                fontSize: 11.sp, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          doc['price'] == 0.00
                              ? 'Varies'
                              : '${doc['price'].toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF233446)),
                        ),
                      ),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ----SUCCESS SCREEN ----

class SuccessfulScreen extends StatelessWidget {
  final PendingRequest request;

  const SuccessfulScreen({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 120.r,
                width: 120.r,
                decoration: const BoxDecoration(
                  color: Color(0xFF9DB2BF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 80.r,
                ),
              ),
              SizedBox(height: 30.h),
              CustomFont(
                text: "Request Submitted Successfully",
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              Text(
                "Your document request has been submitted and is now pending for processing. You can check the status of your request in the Pending section.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.sp, color: Colors.black54),
              ),
              SizedBox(height: 50.h),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(
                        initialIndex: 1,
                        newRequest: request,
                      ),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27374D),
                  fixedSize: Size(340.w, 50.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  elevation: 5,
                ),
                child: CustomFont(
                  text: "Proceed",
                  fontSize: 18.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
