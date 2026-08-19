import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:capstone_project/widgets/simple_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ChangePasswordHandler = Future<void> Function(
  String currentPassword,
  String newPassword,
);

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.changePasswordHandler,
  });

  final ChangePasswordHandler? changePasswordHandler;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _pageBackground = Color(0xFFF5F7F9);
  static const _primaryBlue = Color(0xFF5A819B);
  static const _darkNavy = Color(0xFF233446);

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_refreshRequirements);
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_refreshRequirements);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _refreshRequirements() {
    if (mounted) setState(() {});
  }

  bool _validLength(String value) => value.length >= 8 && value.length <= 72;
  bool _hasLetterCases(String value) =>
      RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value);
  bool _hasNumber(String value) => RegExp(r'[0-9]').hasMatch(value);
  bool _hasSpecial(String value) =>
      RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value);
  bool _hasNoSpaces(String value) => !RegExp(r'\s').hasMatch(value);

  bool _isStrongPassword(String value) {
    return _validLength(value) &&
        _hasLetterCases(value) &&
        _hasNumber(value) &&
        _hasSpecial(value) &&
        _hasNoSpaces(value);
  }

  String? _validateCurrentPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your current password';
    if (value.length > 72) return 'Current password is too long';
    return null;
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a new password';
    if (!_isStrongPassword(password)) {
      return 'Complete all password requirements below';
    }
    if (password == _currentPasswordController.text) {
      return 'New password must be different';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your new password';
    if (value != _newPasswordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _changePassword() async {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      final handler = widget.changePasswordHandler;
      if (handler != null) {
        await handler(
          _currentPasswordController.text,
          _newPasswordController.text,
        );
      } else {
        await MongoDataApiService.instance.changePassword(
          currentPassword: _currentPasswordController.text,
          newPassword: _newPasswordController.text,
        );
      }
      if (!mounted) return;

      setState(() => _isSubmitting = false);
      TextInput.finishAutofillContext();
      await showSimpleMessageDialog(
        context,
        'Your password was changed. Other signed-in devices have been signed out.',
        title: 'Password changed',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Could not change password',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final password = _newPasswordController.text;
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          key: const Key('change_password_back_button'),
          tooltip: 'Back to profile',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Change password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 32.0 : 16.0;
            return AutofillGroup(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: _buildPasswordForm(password),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPasswordForm(String password) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Password details',
            style: TextStyle(
              color: _darkNavy,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          _passwordField(
            fieldKey: const Key('change_current_password_field'),
            controller: _currentPasswordController,
            label: 'Current password',
            visible: _showCurrentPassword,
            validator: _validateCurrentPassword,
            autofillHints: const [AutofillHints.password],
            onToggle: () => setState(
              () => _showCurrentPassword = !_showCurrentPassword,
            ),
          ),
          const SizedBox(height: 14),
          _passwordField(
            fieldKey: const Key('change_new_password_field'),
            controller: _newPasswordController,
            label: 'New password',
            visible: _showNewPassword,
            validator: _validateNewPassword,
            autofillHints: const [AutofillHints.newPassword],
            onToggle: () => setState(
              () => _showNewPassword = !_showNewPassword,
            ),
          ),
          const SizedBox(height: 12),
          _requirement('8-72 characters', _validLength(password)),
          _requirement(
            'Uppercase and lowercase letters',
            _hasLetterCases(password),
          ),
          _requirement('At least one number', _hasNumber(password)),
          _requirement(
            'At least one special character',
            _hasSpecial(password),
          ),
          _requirement('No spaces', _hasNoSpaces(password)),
          const SizedBox(height: 14),
          _passwordField(
            fieldKey: const Key('change_confirm_password_field'),
            controller: _confirmPasswordController,
            label: 'Confirm new password',
            visible: _showConfirmation,
            validator: _validateConfirmation,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _changePassword(),
            onToggle: () => setState(
              () => _showConfirmation = !_showConfirmation,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('change_password_submit_button'),
              onPressed: _isSubmitting ? null : _changePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkNavy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFDDE3E7),
                disabledForegroundColor: const Color(0xFF7B878F),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
                  : const Icon(Icons.lock_reset_rounded),
              label: Text(
                _isSubmitting ? 'Changing password...' : 'Change password',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required bool visible,
    required String? Function(String?) validator,
    required Iterable<String> autofillHints,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      validator: validator,
      obscureText: !visible,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: visible ? 'Hide password' : 'Show password',
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryBlue, width: 2),
        ),
      ),
    );
  }

  Widget _requirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 17,
            color: met ? const Color(0xFF2E7D32) : const Color(0xFF82909A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: met ? const Color(0xFF2E7D32) : const Color(0xFF687680),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
