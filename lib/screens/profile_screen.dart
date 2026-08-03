import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/screens/edit_profile_screen.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:capstone_project/widgets/profile_avatar.dart';
import 'package:capstone_project/widgets/simple_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onBack, this.onProfileChanged});

  /// Used when this screen is hosted inside a tab/page shell. When omitted,
  /// the back button falls back to the current Navigator.
  final VoidCallback? onBack;
  final ValueChanged<ProfileData>? onProfileChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileData? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await MongoDataApiService.instance.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
      });
      widget.onProfileChanged?.call(profile);
    } catch (error) {
      if (!mounted) return;
      await showSimpleMessageDialog(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        title: 'Profile failed',
      );
      setState(() {
        _errorMessage = 'Unable to load profile.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.maybePop(context);
  }

  PreferredSizeWidget _buildStateAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF5D7E97),
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        key: const Key('profile_back_button'),
        tooltip: 'Back to home',
        onPressed: _handleBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text(
        'Profile',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Colors based on your theme
    const Color headerBlue = Color(0xFF5D7E97);
    const Color darkNavy = Color(0xFF233446);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildStateAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildStateAppBar(),
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: _loadProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: darkNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18.r),
                    ),
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildStateAppBar(),
        body: Center(
          child: Text(
            'No profile data found.',
            style: TextStyle(fontSize: 14.sp, color: Colors.black87),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Section: Header and Avatar
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 160.h,
                  width: double.infinity,
                  color: headerBlue,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding:
                          EdgeInsets.only(left: 8.w, right: 20.w, top: 4.h),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconButton(
                            key: const Key('profile_back_button'),
                            tooltip: 'Back to home',
                            onPressed: _handleBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: Colors.white,
                          ),
                          SizedBox(width: 4.w),
                          Padding(
                            padding: EdgeInsets.only(top: 5.h),
                            child: Text(
                              'Profile',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -50.h,
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    padding: EdgeInsets.all(5.r),
                    child: ProfileAvatar(
                      key: const Key('profile_screen_avatar'),
                      size: 110.r,
                      backgroundColor: headerBlue,
                      imageUrl: profile.profileImageUrl,
                      iconColor: Colors.white,
                      iconSize: 72.r,
                      semanticLabel: '${profile.fullName} profile photo',
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 70.h),

            // Basic Information Card (View Only)
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(horizontal: 20.w),
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15.r),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Personal Information",
                    style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20.h),
                  _buildInfoRow("Name:", profile.fullName),
                  _buildInfoRow("Account type:", profile.roleLabel),
                  if (profile.isCurrentStudent)
                    _buildInfoRow("Student ID:", profile.studentId),
                  _buildInfoRow(
                    "${profile.academicYearLabel}:",
                    profile.yearLevel,
                  ),
                  _buildInfoRow(
                    "${profile.programLabel}:",
                    profile.program,
                  ),
                  if (profile.usesSchoolLogin)
                    _buildInfoRow(
                      "School / login email:",
                      profile.schoolEmail,
                    )
                  else
                    _buildInfoRow("Login email:", profile.personalEmail),
                ],
              ),
            ),

            SizedBox(height: 30.h),

            // Edit Profile Button
            ElevatedButton(
              onPressed: () async {
                final updated = await Navigator.push<ProfileData>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditProfileScreen(profile: profile),
                  ),
                );
                if (!context.mounted) return;
                if (updated != null) {
                  setState(() {
                    _profile = updated;
                  });
                  widget.onProfileChanged?.call(updated);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: darkNavy,
                fixedSize: Size(180.w, 45.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r)),
              ),
              child: Text(
                "Edit profile",
                style: TextStyle(color: Colors.white, fontSize: 20.sp),
              ),
            ),

            SizedBox(height: 80.h),

            // Log out Button
            ElevatedButton(
              onPressed: () async {
                await MongoDataApiService.instance.logout();
                if (!context.mounted) return;
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: darkNavy,
                fixedSize: Size(180.w, 45.h),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r)),
              ),
              child: Text(
                "Log out",
                style: TextStyle(color: Colors.white, fontSize: 20.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to build the row labels and values
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132.w,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.sp, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.black,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
