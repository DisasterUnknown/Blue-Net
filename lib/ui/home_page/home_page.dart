import 'package:bluetooth_chat_app/ui/home_page/widget/add_user_dialog_box.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/app_search_delegate.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/chat_builder.dart';
import 'package:bluetooth_chat_app/ui/info_page/info_page.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 🔹 Sample searchable data (replace with real data later)
  final List<String> searchData = [
    'User 0',
    'User 1',
    'User 2',
  ];

  void _openInfoPage() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const InfoPage(),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // slide up from bottom
          const end = Offset.zero;
          const curve = Curves.easeOut;

          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),

      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        elevation: 0,
        title: const Text(
          'Bluetooth Chat',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),

        actions: [
          // ℹ️ INFO / METRICS PAGE
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Mesh & DB Info',
            onPressed: _openInfoPage,
          ),

          // 🔍 SEARCH
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: AppSearchDelegate(searchData),
              );
            },
          ),
        ],
      ),

      body: buildChatList(
        onContactsChanged: () => setState(() {}),
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent.shade400,
        onPressed: () async {
          final added = await showAddUserDialog(context);
          if (!mounted) return;
          if (added == true) {
            setState(() {}); // reload chat list from DB
          }
        },
        child: const Icon(
          Icons.add_link_outlined,
          size: 30,
          color: Colors.black,
        ),
      ),
    );
  }
}
