import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/screens/edit_profile_screen.dart';
import 'package:capstone_project/services/mongo_data_api_service.dart';
import 'package:capstone_project/widgets/simple_message_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    // Colors based on your theme
    const Color headerBlue = Color(0xFF5D7E97);
    const Color darkNavy = Color(0xFF233446);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
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
        body: Center(
          child: Text(
            'No profile data found.',
            style: TextStyle(fontSize: 14.sp, color: Colors.black87),
          ),
        ),
      );
    }

    final isPastStudent = profile.isPastStudent;

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
                  padding: EdgeInsets.only(left: 20.w, top: 50.h),
                  child: Text(
                    "Profile",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32.sp,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  bottom: -50.h,
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    padding: EdgeInsets.all(5.r),
                    child: CircleAvatar(
                      radius: 55.r,
                      backgroundColor: headerBlue,
                      backgroundImage: profile.profileImageUrl.isNotEmpty
                          ? NetworkImage(profile.profileImageUrl)
                          : null,
                      child: profile.profileImageUrl.isEmpty
                          ? Icon(Icons.person, size: 80.r, color: Colors.black)
                          : null,
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
                    "Basic Information",
                    style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20.h),
                  _buildInfoRow("Name:", profile.fullName),
                  if (isPastStudent) ...[
                    _buildInfoRow(
                      "Year graduated / last attended:",
                      profile.yearLevel,
                    ),
                    _buildInfoRow("Program:", profile.program),
                  ] else ...[
                    _buildInfoRow("Student ID:", profile.studentId),
                    _buildInfoRow("Year level:", profile.yearLevel),
                    _buildInfoRow("Program:", profile.program),
                    _buildInfoRow("School Email:", profile.schoolEmail),
                  ],
                  _buildInfoRow("Login Email:", profile.personalEmail),
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
            width: 100.w,
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
