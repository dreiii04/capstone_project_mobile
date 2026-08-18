import 'dart:io';

import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:capstone_project/widgets/profile_avatar.dart';
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

  bool _isSaving = false;

  List<TextEditingController> get _controllers => [
        _firstNameController,
        _lastNameController,
        _studentIdController,
        _yearLevelController,
        _programController,
        _schoolEmailController,
        _personalEmailController,
      ];

  bool get _hasChanges {
    final profile = widget.profile;
    final accountFieldsChanged = profile.isCurrentStudent &&
        _studentIdController.text.trim() != profile.studentId.trim();
    return _image != null ||
        _firstNameController.text.trim() != profile.firstName.trim() ||
        _lastNameController.text.trim() != profile.lastName.trim() ||
        _yearLevelController.text.trim() != profile.yearLevel.trim() ||
        _programController.text.trim() != profile.program.trim() ||
        accountFieldsChanged;
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

  Future<void> _handleSave() async {
    if (_isSaving || !_hasChanges) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final updated = ProfileData(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      studentId: widget.profile.isCurrentStudent
          ? _studentIdController.text.trim()
          : '',
      yearLevel: _yearLevelController.text.trim(),
      program: _programController.text.trim(),
      schoolEmail:
          widget.profile.usesSchoolLogin ? widget.profile.schoolEmail : '',
      personalEmail:
          widget.profile.usesSchoolLogin ? '' : widget.profile.personalEmail,
      role: widget.profile.role,
    );

    try {
      var saved = await MongoDataApiService.instance.updateProfile(
        profile: updated,
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
        leading: IconButton(
          key: const Key('edit_profile_back_button'),
          tooltip: 'Back to profile',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
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
                    child: ProfileAvatar(
                      size: 84,
                      backgroundColor: const Color(0xFFE8EFF3),
                      iconColor: _primaryBlue,
                      iconSize: 46,
                      imageUrl: _image == null ? _profileImageUrl : '',
                      imageProvider: _image == null ? null : FileImage(_image!),
                      semanticLabel: 'Current profile photo',
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

  Widget _buildPersonalInformationCard() {
    final profile = widget.profile;
    return _buildSectionCard(
      icon: Icons.badge_outlined,
      title: 'Personal information',
      subtitle: 'Fields are tailored to your account type.',
      child: Column(
        children: [
          Container(
            key: const Key('edit_profile_account_type'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7E3EA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  color: _primaryBlue,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account type',
                        style: TextStyle(
                          color: Color(0xFF687680),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.roleLabel,
                        style: const TextStyle(
                          color: _darkNavy,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF7B8992),
                  size: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
          if (profile.isCurrentStudent) ...[
            const SizedBox(height: 14),
            _buildTextField(
              fieldKey: const Key('edit_student_id_field'),
              controller: _studentIdController,
              label: 'Student ID',
              icon: Icons.credit_card_rounded,
              hint: 'e.g. 2026-00001',
            ),
          ],
          const SizedBox(height: 14),
          _buildResponsivePair(
            _buildTextField(
              fieldKey: const Key('edit_academic_year_field'),
              controller: _yearLevelController,
              label: profile.academicYearLabel,
              icon: Icons.calendar_today_outlined,
              hint: profile.academicYearHint,
            ),
            _buildTextField(
              fieldKey: const Key('edit_program_field'),
              controller: _programController,
              label: profile.programLabel,
              icon: Icons.school_outlined,
              hint: profile.programHint,
              textCapitalization: TextCapitalization.words,
            ),
          ),
          if (profile.usesSchoolLogin) ...[
            const SizedBox(height: 14),
            _buildTextField(
              fieldKey: const Key('edit_school_login_email_field'),
              controller: _schoolEmailController,
              label: 'School / login email',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => _validateEmail(value, required: true),
              autofillHints: const [AutofillHints.email],
              helper: 'Your login email cannot be changed.',
              enabled: false,
            ),
          ] else ...[
            const SizedBox(height: 14),
            _buildTextField(
              fieldKey: const Key('edit_login_email_field'),
              controller: _personalEmailController,
              label: 'Login email',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => _validateEmail(value, required: true),
              autofillHints: const [AutofillHints.email],
              helper: 'Your login email cannot be changed.',
              enabled: false,
            ),
          ],
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
    Key? fieldKey,
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
    bool enabled = true,
    bool obscureText = false,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      enabled: enabled,
      obscureText: obscureText,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(color: _darkNavy, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, size: 21),
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
          // A bottom bar receives the full page height as a loose constraint.
          // Shrink-wrap it so it cannot cover the app bar and form.
          heightFactor: 1,
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
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSaving ? 'Saving changes...' : 'Save changes',
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
