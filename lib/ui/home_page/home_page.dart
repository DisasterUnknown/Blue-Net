import 'package:bluetooth_chat_app/ui/home_page/widget/add_user_dialog_box.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/app_search_delegate.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/call_builder.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/chat_builder.dart';
import 'package:bluetooth_chat_app/ui/home_page/widget/status_builder.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 🔹 Sample searchable data (replace with real data later)
  final List<String> searchData = [
    'User 0',
    'User 1',
    'User 2',
    'Status 0',
    'Status 1',
    'Call User 0',
    'Call User 1',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

          // ⋮ MENU
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF2A2A2A),
            onSelected: (value) {
              if (value == 'settings') {
                debugPrint('Settings');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Text('Settings',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          buildChatList(),
          buildStatusList(),
          buildCallList(),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.greenAccent.shade400,
        onPressed: () => showAddUserDialog(context),
        child: const Icon(
          Icons.add_link_outlined,
          size: 30,
          color: Colors.black,
        ),
      ),
    );
  }
}
