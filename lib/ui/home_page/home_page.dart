import 'package:bluetooth_chat_app/services/routing_service.dart';
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
  final List<String> searchData = ['User 0', 'User 1', 'User 2'];

  void _openInfoPage() {
    RoutingService().navigateWithSlide(
      InfoPage()
    );
  }

  void _openLogsPage() {
    RoutingService().navigateWithSlide(
      InfoPage()
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
          // 🪵 Logs / METRICS PAGE
          IconButton(
            icon: const Icon(Icons.dynamic_form_outlined),
            tooltip: 'Mesh & DB Info',
            onPressed: _openLogsPage,
          ),

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

      body: buildChatList(onContactsChanged: () => setState(() {})),

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
