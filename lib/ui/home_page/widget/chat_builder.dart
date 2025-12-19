import 'package:bluetooth_chat_app/ui/chat_page/chat_page.dart';
import 'package:flutter/material.dart';

Widget buildChatList() {
  return ListView.builder(
    itemCount: 10,
    itemBuilder: (context, index) => ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.greenAccent.shade400,
        child: Text('U$index', style: const TextStyle(color: Colors.black)),
      ),
      title: Text('User $index', style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        'Last message from User $index',
        style: TextStyle(color: Colors.grey.shade400),
      ),
      trailing: Text(
        '12:00 PM',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                ChatPage(userName: 'User 1', userId: 'U1'),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  const begin = Offset(1.0, 0.0); // start from right
                  const end = Offset.zero;
                  const curve = Curves.ease;

                  final tween = Tween(
                    begin: begin,
                    end: end,
                  ).chain(CurveTween(curve: curve));

                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
          ),
        );
      },
    ),
  );
}
