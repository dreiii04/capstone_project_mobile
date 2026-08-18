import 'package:capstone_project/constants.dart';
import 'package:flutter/material.dart';

String resolveProfileImageUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return trimmed;
  }

  if (trimmed.startsWith('/uploads/') || trimmed.startsWith('uploads/')) {
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return ApiConstants.originUri.resolve(path).toString();
  }

  return trimmed;
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.size,
    this.imageUrl = '',
    this.imageProvider,
    this.backgroundColor = const Color(0xFFE7EEF3),
    this.iconColor = fbDarkPrimary,
    this.iconSize,
    this.semanticLabel = 'Profile photo',
  });

  final double size;
  final String imageUrl;
  final ImageProvider<Object>? imageProvider;
  final Color backgroundColor;
  final Color iconColor;
  final double? iconSize;
  final String semanticLabel;

  Widget _fallback() {
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          color: iconColor,
          size: iconSize ?? size * 0.52,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveProfileImageUrl(imageUrl);
    final provider = imageProvider ??
        (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://')
            ? NetworkImage(resolvedUrl)
            : null);

    return Semantics(
      image: provider != null,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: provider == null
              ? _fallback()
              : Image(
                  key: ValueKey(resolvedUrl),
                  image: provider,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _fallback(),
                ),
        ),
      ),
    );
  }
}
