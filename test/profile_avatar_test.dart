import 'package:capstone_project/constants.dart';
import 'package:capstone_project/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile image URLs resolve against the configured API host', () {
    final previousBaseUrl = authApiBaseUrl;
    addTearDown(() => authApiBaseUrl = previousBaseUrl);
    authApiBaseUrl = 'http://10.0.2.2:4000';

    expect(
      resolveProfileImageUrl('/uploads/profiles/photo.png'),
      'http://10.0.2.2:4000/uploads/profiles/photo.png',
    );
    expect(
      resolveProfileImageUrl('uploads/profiles/photo.png'),
      'http://10.0.2.2:4000/uploads/profiles/photo.png',
    );
    expect(
      resolveProfileImageUrl('https://res.cloudinary.com/demo/photo.png'),
      'https://res.cloudinary.com/demo/photo.png',
    );
  });

  testWidgets('profile avatar shows a fallback when no image is available',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(size: 64),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(ProfileAvatar)), const Size(64, 64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile avatar falls back when a network image fails',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            size: 64,
            imageUrl: 'https://invalid.example/profile.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
