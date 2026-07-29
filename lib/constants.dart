import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

String authApiBaseUrl = _defaultAuthApiBaseUrl();

String _defaultAuthApiBaseUrl() {
	if (kIsWeb) {
		return 'http://localhost:4000';
	}
	switch (defaultTargetPlatform) {
		case TargetPlatform.android:
			return 'http://10.0.2.2:4000';
		case TargetPlatform.iOS:
		case TargetPlatform.macOS:
			return 'http://localhost:4000';
		case TargetPlatform.windows:
		case TargetPlatform.linux:
		case TargetPlatform.fuchsia:
			return 'http://localhost:4000';
	}
}

Future<void> loadAppConfig() async {
	try {
		final envText = await rootBundle.loadString('.env');
		final parsed = <String, String>{};

		for (final rawLine in envText.split('\n')) {
			final line = rawLine.trim();
			if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
				continue;
			}

			final equalsIndex = line.indexOf('=');
			final key = line.substring(0, equalsIndex).trim();
			var value = line.substring(equalsIndex + 1).trim();
			if ((value.startsWith('"') && value.endsWith('"')) ||
					(value.startsWith("'") && value.endsWith("'"))) {
				value = value.substring(1, value.length - 1);
			}
			parsed[key] = value;
		}

		final configuredBaseUrl = parsed['API_BASE_URL'];
		if (configuredBaseUrl != null && configuredBaseUrl.trim().isNotEmpty) {
			authApiBaseUrl = configuredBaseUrl.trim();
			return;
		}
	} catch (_) {
		// Fall back to the platform-specific default above.
	}
}

const Color fbPrimary = Color(0xFF547792); // Muted Blue
const Color fbSecondary = Color(0xFF94B4C1); // Light Steel Blue
const Color fbDarkPrimary = Color(0xFF213448); // Dark Navy
const Color fbLightPrimary = Color(0xFF2F3640); // Charcoal Grey
const Color fbTextColorWhite = Color(0xFFFFFFFF); // Pure White
const Color fbBackgroundLight = Color(0xFFF2F2F2); // Off-White/Light Grey
