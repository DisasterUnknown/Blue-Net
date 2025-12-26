import 'package:bluetooth_chat_app/services/routing_service.dart';
import 'package:bluetooth_chat_app/ui/chat_page/chat_page.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';

Widget buildChatList({VoidCallback? onContactsChanged}) {
  return FutureBuilder<String>(
    future: AppIdentifier.getId(),
    builder: (context, myIdSnapshot) {
      if (!myIdSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final db = DBHelper();
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getAllUsers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Center(
              child: Text(
                'No users yet. Tap + to add one.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final name = (user['name'] as String?) ?? 'Unknown';
              final userCode = user['userCode'] as String? ?? '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.greenAccent.shade400,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  userCode,
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                onTap: () {
                  RoutingService().navigateWithSlide(
                    begin: Offset(0.0, 1.0),
                    ChatPage(userName: name, userId: userCode),
                  );
                },
                onLongPress: () {
                  _showContactActions(
                    context: context,
                    name: name,
                    userCode: userCode,
                    onChanged: onContactsChanged,
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

void _showContactActions({
  required BuildContext context,
  required String name,
  required String userCode,
  VoidCallback? onChanged,
}) {
  final db = DBHelper();

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1F1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text(
                'Edit Contact Name',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final controller = TextEditingController(text: name);
                final updated = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1F1F1F),
                    title: const Text(
                      'Edit Contact',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Display name',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
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
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );

                if (updated != null && updated.isNotEmpty) {
                  await db.updateUserName(userCode, updated);
                  onChanged?.call();
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete Contact & Chats',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1F1F1F),
                    title: const Text(
                      'Delete Contact',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: Text(
                      'Delete $name and all chats with this contact?',
                      style: TextStyle(color: Colors.grey.shade300),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await db.deleteUserAndChats(userCode);
                  onChanged?.call();
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
