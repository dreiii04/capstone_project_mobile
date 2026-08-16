import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CustomTextFormField extends StatelessWidget {
  final double height;
  final double width;
  final TextEditingController controller;
  final String hintText;
  final double fontSize;
  final double hintTextSize;
  final Color fontColor;
  final bool isObscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final void Function(String?)? onSaved;
  final TextInputType keyboardType;
  final Color bgColor;

  const CustomTextFormField({
    super.key,
    required this.height,
    required this.width,
    required this.controller,
    required this.hintText,
    required this.fontSize,
    required this.hintTextSize,
    required this.fontColor,
    this.isObscure = false,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.keyboardType = TextInputType.text,
    this.bgColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60.h,
      width: double.infinity,
      child: TextFormField(

        controller: controller,
        obscureText: isObscure,
        validator: validator,
        onChanged: onChanged,
        onSaved: onSaved, // ✅ added
        keyboardType: keyboardType,
        cursorColor: fontColor,
     
    
        style: TextStyle(fontSize: fontSize, color: fontColor),
        decoration: InputDecoration(
          filled: true,
          fillColor: bgColor,
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: hintTextSize,
            color: fontColor.withAlpha(191),
          ),
          suffixIcon: suffixIcon,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: const BorderSide(color: Colors.blue),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.r),
            borderSide: const BorderSide(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
