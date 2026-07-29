import 'package:capstone_project/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../constants.dart';
import '../widgets/custom_inkwell_button.dart';
import '../widgets/custom_font.dart';

class ChooseActorScreen extends StatelessWidget {
  const ChooseActorScreen({super.key});

  @override
  Widget build(BuildContext context) {
  
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Top Section: Logo
          Expanded(
            flex: 2,
            child: Center(
              child: Padding(
               padding: EdgeInsets.only(top: 40.h),
               
                child: Image.asset(
                  'assets/logo/logo.png', // Ensure this points to your logo with the tagline
                  height: 80.h,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.image, size: 50.h),
                ),
                
              ),
            ),
          ),
    


          // Bottom Section: Role Selection
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: fbPrimary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30.r),
                  topRight: Radius.circular(30.r),
                ),
              ),

              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomFont(
                    text: 'Welcome to VerifiTOR!',
                    fontSize: 28.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  SizedBox(height: 40.h),
                  CustomFont(
                    text: 'Please Select Your Role',
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                  SizedBox(height: 30.h),

                  // Student Button
                  CustomInkwellButton(
                    buttonName: 'STUDENT',
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                    bgColor: fbBackgroundLight,
                    fontColor: fbDarkPrimary, // Dark navy text
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LogInScreen(),
                        ),
                      );
                    },
                    height: 65.h,
                    width: 280.w,
                  ),

                  SizedBox(height: 25.h),

                  // Alumni Button
                  CustomInkwellButton(
                    buttonName: 'ALUMNI',
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                    bgColor: fbBackgroundLight,
                    fontColor: fbDarkPrimary,
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LogInScreen(),
                        ),
                      );
                    },
                    height: 65.h,
                    width: 280.w,
                  ),
                ],
              ),
            ),
          ),


        ],
      ),
    );
  }
}