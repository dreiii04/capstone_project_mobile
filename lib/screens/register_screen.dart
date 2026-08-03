import 'package:flutter/material.dart';

import '../services/mongo_data_api_service.dart';
import '../widgets/simple_message_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _primaryBlue = Color(0xFF547792);
  static const _darkNavy = Color(0xFF213448);

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _postgraduateProgramController = TextEditingController();

  final _emailRegex =
      RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
  final _nameRegex = RegExp(
    r"^[A-Za-zÀ-ÖØ-öø-ÿĀ-žÑñ][A-Za-zÀ-ÖØ-öø-ÿĀ-žÑñ .’'\-]*$",
  );
  final _programOptions = const [
    'BSIT',
    'BSIT-MWA',
    'BSCS',
    'BSIS',
    'BSECE',
    'BSCE',
    'BSA',
    'BSBA',
    'BSHM',
    'BSTM',
    'BEED',
    'BSED',
  ];
  late final List<String> _graduationYears;
  String? _role;
  String? _academicYear;
  String? _program;
  bool _acceptedTerms = false;
  bool _isPasswordObscure = true;
  bool _isConfirmPasswordObscure = true;
  bool _isSubmitting = false;

  bool get _isAlumni => _role == 'alumni';
  bool get _isFormerStudent => _role == 'former_student';
  bool get _isPostgraduate => _role == 'masters' || _role == 'doctorate';
  String get _resolvedProgram => _isPostgraduate
      ? _postgraduateProgramController.text.trim()
      : _program ?? '';

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    _graduationYears = List.generate(
      currentYear - 1950 + 1,
      (index) => (currentYear - index).toString(),
    );
    _passwordController.addListener(_refreshPasswordRequirements);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_refreshPasswordRequirements);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _postgraduateProgramController.dispose();
    super.dispose();
  }

  void _refreshPasswordRequirements() {
    if (mounted) setState(() {});
  }

  String? _validateName(String? value, String fieldName) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your $fieldName';
    if (name.length < 2 || name.length > 50 || !_nameRegex.hasMatch(name)) {
      return 'Use 2-50 letters; spaces, apostrophes and hyphens are allowed';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  bool _hasMinimumLength(String value) =>
      value.length >= 8 && value.length <= 72;
  bool _hasUpperAndLower(String value) =>
      RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value);
  bool _hasNumber(String value) => RegExp(r'[0-9]').hasMatch(value);
  bool _hasSpecialCharacter(String value) =>
      RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value);
  bool _hasNoSpaces(String value) => !RegExp(r'\s').hasMatch(value);

  bool _isStrongPassword(String value) {
    return _hasMinimumLength(value) &&
        _hasUpperAndLower(value) &&
        _hasNumber(value) &&
        _hasSpecialCharacter(value) &&
        _hasNoSpaces(value);
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password';
    if (!_isStrongPassword(password)) {
      return 'Use 8-72 chars with upper/lowercase, number, symbol, and no spaces';
    }
    return null;
  }

  String? _validatePasswordConfirmation(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _handleRegister() async {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      await MongoDataApiService.instance.createUser(
        role: _role!,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: email,
        password: _passwordController.text,
        yearLevel: _academicYear,
        program: _resolvedProgram,
      );

      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        'Your account was created successfully. You can now log in.',
        title: 'Account created',
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Could not create account',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Image.asset(
                      'assets/logo/logo.png',
                      height: 50,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_outlined,
                        color: _primaryBlue,
                        size: 42,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      key: const Key('registration_back_button'),
                      tooltip: 'Back to login',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: _darkNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
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
                  return Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: AutofillGroup(
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Create an Account',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 25),
                                _buildAccountTypeField(),
                                const SizedBox(height: 15),
                                _textField(
                                  key: const Key('first_name_field'),
                                  controller: _firstNameController,
                                  hint: 'First Name',
                                  validator: (value) =>
                                      _validateName(value, 'first name'),
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [
                                    AutofillHints.givenName,
                                  ],
                                ),
                                const SizedBox(height: 15),
                                _textField(
                                  key: const Key('last_name_field'),
                                  controller: _lastNameController,
                                  hint: 'Last Name',
                                  validator: (value) =>
                                      _validateName(value, 'last name'),
                                  textCapitalization: TextCapitalization.words,
                                  autofillHints: const [
                                    AutofillHints.familyName,
                                  ],
                                ),
                                const SizedBox(height: 15),
                                _textField(
                                  key: const Key('registration_email_field'),
                                  controller: _emailController,
                                  hint: 'Email',
                                  keyboardType: TextInputType.emailAddress,
                                  validator: _validateEmail,
                                  autofillHints: const [AutofillHints.email],
                                ),
                                const SizedBox(height: 15),
                                _buildYearField(),
                                const SizedBox(height: 15),
                                _buildProgramField(),
                                const SizedBox(height: 15),
                                _textField(
                                  key: const Key(
                                    'registration_password_field',
                                  ),
                                  controller: _passwordController,
                                  hint: 'Password',
                                  obscureText: _isPasswordObscure,
                                  validator: _validatePassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  suffixIcon: _visibilityButton(
                                    obscure: _isPasswordObscure,
                                    onPressed: () => setState(
                                      () => _isPasswordObscure =
                                          !_isPasswordObscure,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Password strength: ${_passwordStrength(_passwordController.text)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                _textField(
                                  key: const Key('confirm_password_field'),
                                  controller: _confirmPasswordController,
                                  hint: 'Confirm Password',
                                  obscureText: _isConfirmPasswordObscure,
                                  validator: _validatePasswordConfirmation,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  suffixIcon: _visibilityButton(
                                    obscure: _isConfirmPasswordObscure,
                                    onPressed: () => setState(
                                      () => _isConfirmPasswordObscure =
                                          !_isConfirmPasswordObscure,
                                    ),
                                  ),
                                  onFieldSubmitted: (_) => _handleRegister(),
                                ),
                                const SizedBox(height: 8),
                                _buildTermsField(),
                                const SizedBox(height: 25),
                                SizedBox(
                                  height: 55,
                                  child: ElevatedButton(
                                    key: const Key('create_account_button'),
                                    onPressed:
                                        _isSubmitting ? null : _handleRegister,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _darkNavy,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          const Color(0xFF9EABB3),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Register',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'Already have an account? ',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        'Login',
                                        style: TextStyle(
                                          color: Color(0xFFF2F2F2),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
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

  Widget _buildAccountTypeField() {
    return DropdownButtonFormField<String>(
      key: const Key('account_type_field'),
      initialValue: _role,
      isExpanded: true,
      decoration: _inputDecoration(hint: 'Requester Type'),
      items: const [
        DropdownMenuItem(
          key: Key('account_type_former_student'),
          value: 'former_student',
          child: Text('Former / stopped student'),
        ),
        DropdownMenuItem(
          key: Key('account_type_alumni'),
          value: 'alumni',
          child: Text('Alumni'),
        ),
        DropdownMenuItem(
          key: Key('account_type_masters'),
          value: 'masters',
          child: Text("Master's"),
        ),
        DropdownMenuItem(
          key: Key('account_type_doctorate'),
          value: 'doctorate',
          child: Text('Doctorate'),
        ),
      ],
      onChanged: (value) {
        setState(() {
          _role = value;
          _academicYear = null;
          _program = null;
          _postgraduateProgramController.clear();
        });
      },
      validator: (value) =>
          value == null ? 'Select your account type to continue' : null,
    );
  }

  Widget _buildYearField() {
    final hint = switch (_role) {
      'alumni' => 'Year Graduated',
      'former_student' => 'Year Last Attended',
      'masters' || 'doctorate' => 'Year Graduated / Last Attended',
      _ => 'Year Graduated / Last Attended',
    };
    return DropdownButtonFormField<String>(
      key: ValueKey('academic_year_${_role ?? 'none'}'),
      initialValue: _academicYear,
      isExpanded: true,
      decoration: _inputDecoration(hint: hint),
      items: _graduationYears
          .map(
            (year) => DropdownMenuItem(
              value: year,
              child: Text(year, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _academicYear = value),
      validator: (value) {
        if (_role == null) return null;
        if (value != null) return null;
        if (_isAlumni) return 'Select your year graduated';
        if (_isFormerStudent) return 'Select your year last attended';
        return 'Select your year graduated or last attended';
      },
    );
  }

  Widget _buildProgramField() {
    if (_isPostgraduate) {
      return _textField(
        key: const Key('postgraduate_program_field'),
        controller: _postgraduateProgramController,
        hint: _role == 'doctorate' ? 'Doctorate Program' : "Master's Program",
        textCapitalization: TextCapitalization.words,
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter your program' : null,
      );
    }

    return DropdownButtonFormField<String>(
      key: const Key('program_field'),
      initialValue: _program,
      isExpanded: true,
      decoration: _inputDecoration(hint: 'Program'),
      items: _programOptions
          .map(
            (program) => DropdownMenuItem(
              value: program,
              child: Text(program, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _program = value),
      validator: (value) => value == null ? 'Select your program' : null,
    );
  }

  Widget _buildTermsField() {
    return FormField<bool>(
      initialValue: _acceptedTerms,
      validator: (value) =>
          value == true ? null : 'Accept the Terms and Conditions to continue',
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  key: const Key('registration_terms_checkbox'),
                  value: _acceptedTerms,
                  side: const BorderSide(color: Colors.white70),
                  checkColor: _darkNavy,
                  fillColor: WidgetStateProperty.all(Colors.white),
                  onChanged: (value) {
                    setState(() => _acceptedTerms = value ?? false);
                    field.didChange(value ?? false);
                  },
                ),
                const Expanded(
                  child: Text(
                    'I agree to the Terms and Conditions',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(
                    color: Color(0xFFFFDAD6),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    Iterable<String>? autofillHints,
    bool obscureText = false,
    Widget? suffixIcon,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: _darkNavy, fontSize: 15),
      decoration: _inputDecoration(
        hint: hint,
        suffixIcon: suffixIcon,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: _darkNavy, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD8E0E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFB3261E)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.5),
      ),
    );
  }

  Widget _visibilityButton({
    required bool obscure,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: obscure ? 'Show password' : 'Hide password',
      onPressed: onPressed,
      icon: Icon(
        obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );
  }

  String _passwordStrength(String password) {
    if (password.isEmpty) return 'Enter password';
    if (!_hasMinimumLength(password)) return 'Weak';

    var score = 0;
    if (_hasUpperAndLower(password)) score += 2;
    if (_hasNumber(password)) score++;
    if (_hasSpecialCharacter(password)) score++;
    if (!_hasNoSpaces(password)) return 'Weak';
    if (score <= 2) return 'Weak';
    if (score == 3) return 'Medium';
    return 'Strong';
  }
}
