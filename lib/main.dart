import 'package:capstone_project/constants.dart';
import 'package:capstone_project/screens/data_consent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/request_form_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/forgot_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await loadAppConfig();
  runApp(const Verifitor());
}

class Verifitor extends StatelessWidget {
  const Verifitor({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(412, 715),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Verifitor App',
          initialRoute: '/login',
          routes: {
            '/login': (context) => const LogInScreen(),
            '/register': (context) => const RegisterScreen(),

            // Use onGenerateRoute instead of forcing constructor params
            '/home': (context) => const HomeScreen(),
            '/form': (context) => const RequestFormScreen(),
            '/consent': (context) => const DataConsentScreen(),
            '/profile': (context) => const ProfileScreen(),
            '/pending': (context) => const PendingScreen(
                  requestList: [],
                ),
            '/forgot': (context) => const PasswordScreen(),
          },
        );
      },
    );
  }
}
