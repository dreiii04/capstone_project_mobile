import 'package:flutter/material.dart';

class ApiConstants {
  const ApiConstants._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://verifitor-backend.vercel.app/api',
  );

  static Uri uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  static Uri get originUri {
    final apiUri = Uri.parse(baseUrl);
    return apiUri.replace(path: '', query: null, fragment: null);
  }
}

const Color fbPrimary = Color(0xFF547792); // Muted Blue
const Color fbSecondary = Color(0xFF94B4C1); // Light Steel Blue
const Color fbDarkPrimary = Color(0xFF213448); // Dark Navy
const Color fbLightPrimary = Color(0xFF2F3640); // Charcoal Grey
const Color fbTextColorWhite = Color(0xFFFFFFFF); // Pure White
const Color fbBackgroundLight = Color(0xFFF2F2F2); // Off-White/Light Grey
