import 'dart:io';

import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:capstone_project/widgets/simple_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final ProfileData profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _pageBackground = Color(0xFFF5F7F9);
  static const _primaryBlue = Color(0xFF5A819B);
  static const _darkNavy = Color(0xFF233446);

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  File? _image;
  String _profileImageUrl = '';

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _studentIdController;
  late final TextEditingController _yearLevelController;
  late final TextEditingController _programController;
  late final TextEditingController _schoolEmailController;
  late final TextEditingController _personalEmailController;
  late final TextEditingController _passController;
  late final TextEditingController _confirmPassController;

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  List<TextEditingController> get _controllers => [
        _firstNameController,
        _lastNameController,
        _studentIdController,
        _yearLevelController,
        _programController,
        _schoolEmailController,
        _personalEmailController,
        _passController,
        _confirmPassController,
      ];

  bool get _hasChanges {
    final profile = widget.profile;
    return _image != null ||
        _firstNameController.text.trim() != profile.firstName.trim() ||
        _lastNameController.text.trim() != profile.lastName.trim() ||
        _studentIdController.text.trim() != profile.studentId.trim() ||
        _yearLevelController.text.trim() != profile.yearLevel.trim() ||
        _programController.text.trim() != profile.program.trim() ||
        _schoolEmailController.text.trim() != profile.schoolEmail.trim() ||
        _personalEmailController.text.trim() != profile.personalEmail.trim() ||
        _passController.text.isNotEmpty ||
        _confirmPassController.text.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _profileImageUrl = profile.profileImageUrl;
    _firstNameController = TextEditingController(text: profile.firstName);
    _lastNameController = TextEditingController(text: profile.lastName);
    _studentIdController = TextEditingController(text: profile.studentId);
    _yearLevelController = TextEditingController(text: profile.yearLevel);
    _programController = TextEditingController(text: profile.program);
    _schoolEmailController = TextEditingController(text: profile.schoolEmail);
    _personalEmailController =
        TextEditingController(text: profile.personalEmail);
    _passController = TextEditingController();
    _confirmPassController = TextEditingController();

    for (final controller in _controllers) {
      controller.addListener(_refreshSaveState);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_refreshSaveState)
        ..dispose();
    }
    super.dispose();
  }

  void _refreshSaveState() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (pickedFile != null && mounted) {
        setState(() => _image = File(pickedFile.path));
      }
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        'We could not open your photos. Check the app permission and try again.',
        title: 'Photo unavailable',
      );
    }
  }

  String? _requiredName(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    return null;
  }

  String? _validateEmail(String? value, {bool required = false}) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return required ? 'Email is required' : null;
    final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return validEmail.hasMatch(email) ? null : 'Enter a valid email address';
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty && _confirmPassController.text.isEmpty) return null;
    if (password.length < 8) return 'Use at least 8 characters';
    return null;
  }

  String? _validatePasswordConfirmation(String? value) {
    final confirmation = value ?? '';
    if (_passController.text.isEmpty && confirmation.isEmpty) return null;
    if (confirmation.isEmpty) return 'Confirm your new password';
    if (confirmation != _passController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _handleSave() async {
    if (_isSaving || !_hasChanges) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final updated = ProfileData(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      studentId: _studentIdController.text.trim(),
      yearLevel: _yearLevelController.text.trim(),
      program: _programController.text.trim(),
      schoolEmail: _schoolEmailController.text.trim(),
      personalEmail: _personalEmailController.text.trim(),
      role: widget.profile.role,
    );

    try {
      var saved = await MongoDataApiService.instance.updateProfile(
        profile: updated,
        newPassword:
            _passController.text.isNotEmpty ? _passController.text : null,
      );
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        final fileName = _image!.path.split(Platform.pathSeparator).last;
        try {
          saved = await MongoDataApiService.instance.uploadProfilePhoto(
            bytes: bytes,
            fileName: fileName,
          );
          _profileImageUrl = saved.profileImageUrl;
        } catch (error) {
          if (mounted) {
            await showSimpleMessageDialog(
              context,
              error.toString().replaceFirst('Exception: ', ''),
              title: 'Photo upload failed',
            );
          }
        }
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Could not save changes',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Edit profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pagePadding = constraints.maxWidth >= 600 ? 32.0 : 16.0;
              return Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    24,
                    pagePadding,
                    bottomInset > 0 ? 24 : 112,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfilePhotoCard(),
                          const SizedBox(height: 20),
                          _buildPersonalInformationCard(),
                          const SizedBox(height: 16),
                          _buildPasswordCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: bottomInset > 0 ? null : _buildSaveBar(),
    );
  }

  Widget _buildProfilePhotoCard() {
    final role = widget.profile.roleLabel;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryBlue, Color(0xFF6D95AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Change profile photo',
            child: InkWell(
              onTap: _pickImage,
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: const Color(0xFFE8EFF3),
                      backgroundImage: _avatarImage,
                      child: _avatarImage == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 46,
                              color: _primaryBlue,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _darkNavy,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role.isEmpty ? 'Tap the photo to update it' : role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Choose photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? get _avatarImage {
    if (_image != null) return FileImage(_image!);
    if (_profileImageUrl.isEmpty) return null;
    if (_profileImageUrl.startsWith('http')) {
      return NetworkImage(_profileImageUrl);
    }
    final file = File(_profileImageUrl);
    return file.existsSync() ? FileImage(file) : null;
  }

  Widget _buildPersonalInformationCard() {
    final isPastStudent = widget.profile.isPastStudent;
    return _buildSectionCard(
      icon: Icons.badge_outlined,
      title: 'Personal information',
      subtitle: 'Keep your details accurate so we can identify your requests.',
      child: Column(
        children: [
          _buildResponsivePair(
            _buildTextField(
              controller: _firstNameController,
              label: 'First name',
              icon: Icons.person_outline_rounded,
              validator: _requiredName,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
            ),
            _buildTextField(
              controller: _lastNameController,
              label: 'Last name',
              icon: Icons.person_outline_rounded,
              validator: _requiredName,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.familyName],
            ),
          ),
          if (!isPastStudent) ...[
            const SizedBox(height: 14),
            _buildTextField(
              controller: _studentIdController,
              label: 'Student ID',
              icon: Icons.credit_card_rounded,
              hint: 'e.g. 2026-00001',
            ),
          ],
          const SizedBox(height: 14),
          _buildResponsivePair(
            _buildTextField(
              controller: _yearLevelController,
              label: isPastStudent
                  ? 'Year graduated / last attended'
                  : 'Year level',
              icon: Icons.calendar_today_outlined,
              hint: isPastStudent ? 'e.g. 2025' : 'e.g. 4th Year',
            ),
            _buildTextField(
              controller: _programController,
              label: 'Program',
              icon: Icons.school_outlined,
              hint: 'e.g. BS Information Technology',
              textCapitalization: TextCapitalization.words,
            ),
          ),
          if (!isPastStudent) ...[
            const SizedBox(height: 14),
            _buildTextField(
              controller: _schoolEmailController,
              label: 'School email',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              autofillHints: const [AutofillHints.email],
            ),
          ],
          const SizedBox(height: 14),
          _buildTextField(
            controller: _personalEmailController,
            label: 'Login email',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (value) => _validateEmail(value, required: true),
            autofillHints: const [AutofillHints.email],
            helper: 'You will use this email to sign in.',
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    return _buildSectionCard(
      icon: Icons.lock_outline_rounded,
      title: 'Password',
      subtitle: 'Leave both fields blank if you do not want to change it.',
      child: Column(
        children: [
          _buildTextField(
            controller: _passController,
            label: 'New password',
            icon: Icons.key_rounded,
            obscureText: _obscurePass,
            validator: _validatePassword,
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: _visibilityButton(
              obscure: _obscurePass,
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _confirmPassController,
            label: 'Confirm new password',
            icon: Icons.key_rounded,
            obscureText: _obscureConfirm,
            validator: _validatePasswordConfirmation,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            suffixIcon: _visibilityButton(
              obscure: _obscureConfirm,
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            onFieldSubmitted: (_) => _handleSave(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _darkNavy,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF687680),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
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

  Widget _buildResponsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 540) {
          return Column(
            children: [first, const SizedBox(height: 14), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? helper,
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
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: _darkNavy, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, size: 21),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
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
          borderSide: const BorderSide(color: _primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB3261E)),
        ),
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

  Widget _buildSaveBar() {
    final canSave = _hasChanges && !_isSaving;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE2E8EC))),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('save_profile_button'),
                onPressed: canSave ? _handleSave : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _darkNavy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFDDE3E7),
                  disabledForegroundColor: const Color(0xFF7B878F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_hasChanges ? Icons.check_rounded : Icons.done_all),
                label: Text(
                  _isSaving
                      ? 'Saving changes...'
                      : _hasChanges
                          ? 'Save changes'
                          : 'No changes to save',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
