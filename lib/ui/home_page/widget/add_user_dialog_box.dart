import 'dart:ui';

import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showAddUserDialog(BuildContext context) async {
  final myId = await AppIdentifier.getId();

  final otherIdController = TextEditingController();
  final nameController = TextEditingController();

  if (!context.mounted) return;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Blur',
    barrierColor: Colors.black.withValues(alpha: 0.4), // dark overlay
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, __) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Center(
          child: AlertDialog(
            backgroundColor: const Color(0xFF1F1F1F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Add New User',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// 🔐 YOUR UNIQUE ID
                  const Text(
                    'Your Unique ID',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            myId,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white70),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: myId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ID copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// 👤 OTHER USER ID
                  _darkTextField(
                    controller: otherIdController,
                    label: 'Other Person ID',
                    hint: 'Enter 10-character ID',
                  ),

                  const SizedBox(height: 12),

                  /// ✏️ USER NAME
                  _darkTextField(
                    controller: nameController,
                    label: 'User Name',
                    hint: 'Give a display name',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final otherId = otherIdController.text.trim();
                  final name = nameController.text.trim();

                  if (otherId.length != 10 || name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter valid ID and name')),
                    );
                    return;
                  }

                  // TODO: Save user / start Bluetooth pairing
                  debugPrint('Added User → ID: $otherId | Name: $name');

                  Navigator.pop(context);
                },
                child: const Text('Add User'),
              ),
            ],
          ),
        ),
      );
    },
  );
}


Widget _darkTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }