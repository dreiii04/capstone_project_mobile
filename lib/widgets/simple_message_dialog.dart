import 'package:flutter/material.dart';

Future<void> showSimpleMessageDialog(
  BuildContext context,
  String message, {
  String title = 'Notice',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}