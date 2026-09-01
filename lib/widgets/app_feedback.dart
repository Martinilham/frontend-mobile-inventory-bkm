import 'package:flutter/material.dart';

Future<void> showAppPopup(
  BuildContext context, {
  required String title,
  required String message,
  bool success = true,
}) {
  final color = success ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
  final icon = success ? Icons.check_circle_outline : Icons.error_outline;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
