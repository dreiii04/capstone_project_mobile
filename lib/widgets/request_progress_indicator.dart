import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class RequestProgressIndicator extends StatelessWidget {
  const RequestProgressIndicator({
    super.key,
    required this.currentStep,
    this.labels = const ['Consent', 'Details', 'Submit'],
  });

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final activeStep = currentStep.clamp(0, labels.length - 1);

    return Semantics(
      label: 'Request progress: ${labels[activeStep]}, '
          'step ${activeStep + 1} of ${labels.length}',
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(12.w, 2.h, 12.w, 9.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: List.generate(labels.length, (index) {
                final reached = index <= activeStep;
                return Expanded(
                  child: Container(
                    height: 5.h,
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    decoration: BoxDecoration(
                      color: reached
                          ? const Color(0xFF5A819B)
                          : const Color(0xFFE5E9EC),
                      borderRadius: BorderRadius.circular(3.r),
                    ),
                  ),
                );
              }),
            ),
            SizedBox(height: 7.h),
            Row(
              children: List.generate(labels.length, (index) {
                final isCurrent = index == activeStep;
                return Expanded(
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF243746)
                          : const Color(0xFF8B949A),
                      fontSize: 10.sp,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
