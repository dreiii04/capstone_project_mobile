import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/mongo_data_api_service.dart';
import '../widgets/simple_message_dialog.dart';

typedef PasswordResetOtpRequester = Future<String?> Function(String email);
typedef PasswordResetOtpVerifier = Future<String> Function(
  String email,
  String otp,
);
typedef PasswordResetHandler = Future<void> Function(
  String resetToken,
  String newPassword,
);

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({
    super.key,
    this.otpRequester,
    this.otpVerifier,
    this.passwordResetHandler,
  });

  final PasswordResetOtpRequester? otpRequester;
  final PasswordResetOtpVerifier? otpVerifier;
  final PasswordResetHandler? passwordResetHandler;

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  static const _primaryBlue = Color(0xFF547792);
  static const _darkNavy = Color(0xFF213448);

  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _emailRegex =
      RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  bool _codeSent = false;
  bool _isBusy = false;
  String _sentEmail = '';
  String? _devOtp;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your registered email';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validateOtp(String? value) {
    final otp = value?.trim() ?? '';
    if (otp.isEmpty) return 'Enter the six-digit code';
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      return 'The verification code must contain six digits';
    }
    return null;
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _requestOtp({bool isResend = false}) async {
    if (_isBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (!isResend && !(_emailFormKey.currentState?.validate() ?? false)) {
      return;
    }

    final email =
        isResend ? _sentEmail : _emailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      final requester = widget.otpRequester;
      final otp = requester != null
          ? await requester(email)
          : await MongoDataApiService.instance
              .requestPasswordResetOtp(email: email);
      if (!mounted) return;

      _otpController.clear();
      setState(() {
        _sentEmail = email;
        _codeSent = true;
        _devOtp = kDebugMode ? otp : null;
        _isBusy = false;
      });
      _startResendCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNode.requestFocus();
      });
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Could not send code',
      );
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isBusy || !_codeSent) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_otpFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isBusy = true);
    try {
      final verifier = widget.otpVerifier;
      final resetToken = verifier != null
          ? await verifier(_sentEmail, _otpController.text)
          : await MongoDataApiService.instance.verifyPasswordResetOtp(
              email: _sentEmail,
              otp: _otpController.text,
            );
      if (!mounted) return;

      _resendTimer?.cancel();
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            resetToken: resetToken,
            passwordResetHandler: widget.passwordResetHandler,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Code not verified',
      );
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _changeEmail() {
    _resendTimer?.cancel();
    _otpController.clear();
    setState(() {
      _codeSent = false;
      _sentEmail = '';
      _devOtp = null;
      _resendSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Image.asset(
                  'assets/logo/logo.png',
                  height: 80,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_outlined,
                    color: _primaryBlue,
                    size: 50,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _primaryBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 600 ? 36.0 : 25.0;
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 30,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 22),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _codeSent
                                  ? _buildOtpStep()
                                  : _buildEmailStep(),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _isBusy
                                  ? null
                                  : () => Navigator.pushNamedAndRemoveUntil(
                                        context,
                                        '/login',
                                        (route) => false,
                                      ),
                              child: const Text(
                                'Back to Login',
                                style: TextStyle(
                                  color: Color(0xFFF2F2F2),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'Forgot Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _codeSent
              ? 'Enter the six-digit code we sent. The code expires in 10 minutes.'
              : 'Enter your registered email to receive a One-Time Password (OTP).',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return _card(
      key: const ValueKey('email_step'),
      child: Form(
        key: _emailFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Find your account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('forgot_email_field'),
              controller: _emailController,
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _requestOtp(),
              decoration: _inputDecoration(
                label: 'Registered email',
                icon: Icons.mail_outline_rounded,
                hint: 'name@example.com',
              ),
            ),
            const SizedBox(height: 18),
            _primaryButton(
              key: const Key('send_reset_code_button'),
              onPressed: _isBusy ? null : () => _requestOtp(),
              loading: _isBusy,
              loadingLabel: 'Sending code...',
              label: 'Send verification code',
              icon: Icons.send_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpStep() {
    return _card(
      key: const ValueKey('otp_step'),
      child: Form(
        key: _otpFormKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1F5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mail_outline_rounded, color: _primaryBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Code sent to',
                          style: TextStyle(
                            color: Color(0xFF687680),
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          _sentEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _darkNavy,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('change_reset_email_button'),
                    onPressed: _isBusy ? null : _changeEmail,
                    child: const Text(
                      'Change',
                      style: TextStyle(color: _darkNavy),
                    ),
                  ),
                ],
              ),
            ),
            if (_devOtp != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE09A)),
                ),
                child: Text(
                  'Development code: $_devOtp',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF694A00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextFormField(
              key: const Key('reset_otp_field'),
              controller: _otpController,
              focusNode: _otpFocusNode,
              validator: _validateOtp,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (_) => _verifyOtp(),
              style: const TextStyle(
                color: _darkNavy,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
              ),
              decoration: _inputDecoration(
                label: 'Six-digit verification code',
                icon: Icons.password_rounded,
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "Didn't receive the code?",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                TextButton(
                  key: const Key('resend_reset_code_button'),
                  onPressed: _isBusy || _resendSeconds > 0
                      ? null
                      : () => _requestOtp(isResend: true),
                  child: Text(
                    _resendSeconds > 0
                        ? 'Resend in 00:${_resendSeconds.toString().padLeft(2, '0')}'
                        : 'Resend code',
                    style: const TextStyle(color: Color(0xFFF2F2F2)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _primaryButton(
              key: const Key('verify_reset_code_button'),
              onPressed: _isBusy ? null : _verifyOtp,
              loading: _isBusy,
              loadingLabel: 'Verifying code...',
              label: 'Verify code',
              icon: Icons.verified_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Key key, required Widget child}) {
    return Container(
      key: key,
      padding: EdgeInsets.zero,
      child: child,
    );
  }

  Widget _primaryButton({
    required Key key,
    required VoidCallback? onPressed,
    required bool loading,
    required String loadingLabel,
    required String label,
    required IconData icon,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        key: key,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF9EABB3),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(
          loading ? loadingLabel : label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 21),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB3261E)),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.resetToken,
    this.passwordResetHandler,
  });

  final String resetToken;
  final PasswordResetHandler? passwordResetHandler;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _primaryBlue = Color(0xFF547792);
  static const _darkNavy = Color(0xFF213448);

  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_refreshRequirements);
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_refreshRequirements);
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

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a new password';
    if (!_isStrongPassword(password)) {
      return 'Complete all password requirements below';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your new password';
    if (value != _newPasswordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _resetPassword() async {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      final handler = widget.passwordResetHandler;
      if (handler != null) {
        await handler(widget.resetToken, _newPasswordController.text);
      } else {
        await MongoDataApiService.instance.resetPassword(
          resetToken: widget.resetToken,
          newPassword: _newPasswordController.text,
        );
      }
      if (!mounted) return;

      TextInput.finishAutofillContext();
      await showSimpleMessageDialog(
        context,
        'Your password was updated. You can now log in with your new password.',
        title: 'Password reset complete',
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Could not reset password',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final password = _newPasswordController.text;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Image.asset(
                  'assets/logo/logo.png',
                  height: 120,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_outlined,
                    color: _primaryBlue,
                    size: 50,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _primaryBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 600 ? 36.0 : 25.0;
                  return AutofillGroup(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 30,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: _buildResetForm(password),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm(String password) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reset Password',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 25),
          TextFormField(
            key: const Key('new_password_field'),
            controller: _newPasswordController,
            validator: _validateNewPassword,
            obscureText: !_isNewPasswordVisible,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _passwordDecoration(
              label: 'New Password',
              visible: _isNewPasswordVisible,
              onToggle: () => setState(
                () => _isNewPasswordVisible = !_isNewPasswordVisible,
              ),
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
          TextFormField(
            key: const Key('confirm_new_password_field'),
            controller: _confirmPasswordController,
            validator: _validateConfirmation,
            obscureText: !_isConfirmPasswordVisible,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _resetPassword(),
            decoration: _passwordDecoration(
              label: 'Confirm Password',
              visible: _isConfirmPasswordVisible,
              onToggle: () => setState(
                () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
              ),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              key: const Key('reset_password_button'),
              onPressed: _isSubmitting ? null : _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkNavy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF9EABB3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                _isSubmitting ? 'Resetting...' : 'Reset Password',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    ),
            child: const Text(
              'Back to Login',
              style: TextStyle(
                color: Color(0xFFF2F2F2),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _passwordDecoration({
    required String label,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      hintText: label,
      suffixIcon: IconButton(
        tooltip: visible ? 'Hide password' : 'Show password',
        onPressed: onToggle,
        icon: Icon(
          visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB3261E)),
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
            color: met ? const Color(0xFFB9F6CA) : Colors.white70,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: met ? const Color(0xFFB9F6CA) : Colors.white70,
                fontSize: 12,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
