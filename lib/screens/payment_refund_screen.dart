import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/mongo_data_api_service.dart';
import '../widgets/simple_message_dialog.dart';
import 'history_screen.dart';

class PaymentRefundScreen extends StatefulWidget {
  const PaymentRefundScreen({super.key, required this.item});

  final HistoryItem item;

  @override
  State<PaymentRefundScreen> createState() => _PaymentRefundScreenState();
}

class _PaymentRefundScreenState extends State<PaymentRefundScreen> {
  static const _primaryBlue = Color(0xFF5A819B);
  static const _darkNavy = Color(0xFF233446);
  static const _background = Color(0xFFF5F7F9);

  final _formKey = GlobalKey<FormState>();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _reasonController = TextEditingController(
    text: 'My paid document request was rejected.',
  );

  String _refundMethod = 'gcash';
  bool _confirmed = false;
  bool _isSubmitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _bankNameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String get _formattedAmount {
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: 'PHP ',
      decimalDigits: 2,
    ).format(widget.item.totalAmount);
  }

  Future<void> _submitRefund() async {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    if (!_confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm that the refund details are correct.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await MongoDataApiService.instance.requestRefund(
        transactionId: widget.item.transactionId,
        refundMethod: _refundMethod,
        accountName: _accountNameController.text,
        accountNumber: _accountNumberController.text,
        bankName:
            _refundMethod == 'bank_transfer' ? _bankNameController.text : null,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      widget.item.refundStatus =
          result['refundStatus']?.toString().trim().isNotEmpty == true
              ? result['refundStatus'].toString().trim()
              : 'pending';
      setState(() {
        _submitted = true;
        _isSubmitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Refund request failed',
      );
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Request refund',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 32.0 : 16.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _submitted ? _buildSuccessState() : _buildRefundForm(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefundForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNotice(),
          const SizedBox(height: 16),
          _buildSummaryCard(),
          const SizedBox(height: 16),
          _buildRefundProcessCard(),
          const SizedBox(height: 16),
          _buildDetailsCard(),
          const SizedBox(height: 16),
          _buildConfirmation(),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('submit_refund_button'),
              onPressed: _isSubmitting ? null : _submitRefund,
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.currency_exchange_rounded),
              label: Text(
                _isSubmitting
                    ? 'Submitting request...'
                    : 'Submit refund request',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD1CD)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB42318)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'This paid request was rejected. To return your payment, submit the receiving account below. The office will verify the payment and refund details before sending it back.',
              style: TextStyle(
                color: Color(0xFF7A271A),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundProcessCard() {
    return _card(
      title: 'How the refund works',
      icon: Icons.route_outlined,
      child: const Column(
        children: [
          _RefundStep(
            number: '1',
            title: 'Provide a receiving account',
            description:
                'Choose GCash or bank transfer and check the account details carefully.',
          ),
          SizedBox(height: 16),
          _RefundStep(
            number: '2',
            title: 'Wait for office verification',
            description:
                'The Registrar will confirm the rejected request, payment, and refund destination.',
          ),
          SizedBox(height: 16),
          _RefundStep(
            number: '3',
            title: 'Follow the status in History',
            description:
                'You will receive a notification when the refund status changes or more information is needed.',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return _card(
      title: 'Refund summary',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          _summaryRow('Document', widget.item.title),
          const Divider(height: 24),
          _summaryRow('Payment method', _paymentMethodLabel),
          const Divider(height: 24),
          _summaryRow('Refund amount', _formattedAmount, emphasize: true),
        ],
      ),
    );
  }

  String get _paymentMethodLabel {
    final type = widget.item.paymentType.trim().toLowerCase();
    if (type == 'receipt' || type == 'gcash') return 'GCash';
    if (type == 'onsite') return 'Other online payment';
    return widget.item.paymentType;
  }

  Widget _buildDetailsCard() {
    return _card(
      title: 'Refund destination',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _refundMethod,
            decoration: _inputDecoration(
              label: 'Refund method',
              icon: Icons.payments_outlined,
            ),
            items: const [
              DropdownMenuItem(value: 'gcash', child: Text('GCash')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _refundMethod = value;
                _accountNumberController.clear();
              });
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _accountNameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              label: 'Account holder name',
              icon: Icons.person_outline_rounded,
              hint: 'Name registered on the account',
            ),
            validator: (value) {
              if ((value?.trim().length ?? 0) < 2) {
                return 'Enter the account holder name';
              }
              return null;
            },
          ),
          if (_refundMethod == 'bank_transfer') ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _bankNameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration(
                label: 'Bank name',
                icon: Icons.account_balance_outlined,
                hint: 'e.g. BDO, BPI, Metrobank',
              ),
              validator: (value) {
                if (_refundMethod == 'bank_transfer' &&
                    (value?.trim().isEmpty ?? true)) {
                  return 'Enter the bank name';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _accountNumberController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: _refundMethod == 'gcash' ? 11 : 30,
            decoration: _inputDecoration(
              label: _refundMethod == 'gcash'
                  ? 'GCash mobile number'
                  : 'Bank account number',
              icon: _refundMethod == 'gcash'
                  ? Icons.phone_android_rounded
                  : Icons.numbers_rounded,
              hint: _refundMethod == 'gcash' ? '09XXXXXXXXX' : null,
            ),
            validator: (value) {
              final number = value?.trim() ?? '';
              if (_refundMethod == 'gcash' &&
                  !RegExp(r'^09\d{9}$').hasMatch(number)) {
                return 'Enter a valid 11-digit GCash number';
              }
              if (_refundMethod == 'bank_transfer' &&
                  (number.length < 6 || number.length > 30)) {
                return 'Enter a valid account number';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _reasonController,
            minLines: 3,
            maxLines: 5,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: _inputDecoration(
              label: 'Reason or note',
              icon: Icons.notes_rounded,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: CheckboxListTile(
        key: const Key('refund_confirmation_checkbox'),
        value: _confirmed,
        onChanged: (value) => setState(() => _confirmed = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: _primaryBlue,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        title: const Text(
          'I confirm that the refund details are correct.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Incorrect account information may delay your refund.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8EC)),
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: const BoxDecoration(
              color: Color(0xFFE6F4EA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 46,
              color: Color(0xFF218739),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Refund requested',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _darkNavy,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your $_formattedAmount refund for ${widget.item.title} is now under review. Track it in History; you will also receive a notification when its status changes.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF687680),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
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
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 124,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF687680), fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: emphasize ? const Color(0xFF218739) : _darkNavy,
              fontSize: emphasize ? 16 : 14,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    bool alignLabelWithHint = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon: Icon(icon, size: 21),
      filled: true,
      fillColor: const Color(0xFFF8FAFB),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}

class _RefundStep extends StatelessWidget {
  const _RefundStep({
    required this.number,
    required this.title,
    required this.description,
    this.isLast = false,
  });

  final String number;
  final String title;
  final String description;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFEAF1F5),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: _PaymentRefundScreenState._primaryBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _PaymentRefundScreenState._darkNavy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF687680),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
