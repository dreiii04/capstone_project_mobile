import 'package:capstone_project/models/profile_data.dart';
import 'package:capstone_project/screens/home_screen.dart';
import 'package:capstone_project/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = ProfileData(
  firstName: 'Jose',
  lastName: 'Rizal',
  studentId: '',
  yearLevel: '1896',
  program: 'Medicine',
  schoolEmail: '',
  personalEmail: 'jose@example.com',
  role: 'alumni',
  profileImageUrl: 'https://res.cloudinary.com/demo/profile.png',
);

void main() {
  testWidgets('home header uses the profile image and larger branding',
      (tester) async {
    tester.view.physicalSize = const Size(412, 715);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(412, 715),
        builder: (_, __) => const MaterialApp(
          home: HomeScreen(initialProfile: _profile),
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatar>(
      find.byKey(const Key('home_profile_avatar')),
    );
    expect(avatar.imageUrl, _profile.profileImageUrl);
    expect(avatar.size, 54);

    final welcome = tester.widget<Text>(
      find.byKey(const Key('home_welcome_text')),
    );
    expect(welcome.data, contains('Jose'));
    expect(
      welcome.data,
      anyOf(
        startsWith('Good morning'),
        startsWith('Good afternoon'),
        startsWith('Good evening'),
      ),
    );
    expect(welcome.maxLines, 2);
    expect(welcome.overflow, TextOverflow.ellipsis);
    expect(welcome.textAlign, TextAlign.start);
    expect(welcome.style?.fontSize, 16);
    expect(welcome.style?.fontWeight, FontWeight.w700);

    final welcomeTitle = tester.widget<Text>(
      find.byKey(const Key('home_welcome_title')),
    );
    expect(welcomeTitle.data, 'WELCOME TO');
    expect(welcomeTitle.textAlign, TextAlign.center);
    expect(welcomeTitle.style?.fontSize, 20);
    expect(welcomeTitle.style?.fontWeight, FontWeight.w800);

    final brandPanel = tester.widget<Container>(
      find.byKey(const Key('home_brand_block')),
    );
    final panelDecoration = brandPanel.decoration! as BoxDecoration;
    expect(panelDecoration.color, Colors.transparent);
    expect(panelDecoration.borderRadius, isNotNull);
    expect(panelDecoration.boxShadow, isNull);

    final logo = tester.widget<Image>(
      find.byKey(const Key('home_brand_logo')),
    );
    expect(logo.width, 200);
    expect(logo.height, 65);
    expect(logo.alignment, Alignment.center);
    expect(logo.semanticLabel, 'VerifiTOR');

    expect(
      tester.getSize(find.byKey(const Key('home_request_overview'))).height,
      325,
    );
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);

    final requestTitle = tester.widget<Text>(find.text('My requests'));
    expect(requestTitle.style?.fontSize, 20);

    final requestButtonText = tester.widget<Text>(find.text('New request'));
    expect(requestButtonText.style?.fontSize, 14);

    final avatarCenter = tester.getCenter(
      find.byKey(const Key('home_profile_avatar')),
    );
    final greetingRect = tester.getRect(
      find.byKey(const Key('home_welcome_text')),
    );
    expect(greetingRect.left, greaterThan(avatarCenter.dx));
    expect(tester.getCenter(find.byKey(const Key('home_welcome_title'))).dx,
        closeTo(206, 1));
    expect(tester.getCenter(find.byKey(const Key('home_brand_logo'))).dx,
        closeTo(206, 1));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
