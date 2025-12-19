import 'package:flutter/material.dart';

class AppSearchDelegate extends SearchDelegate<String> {
  final List<String> data;

  AppSearchDelegate(this.data);

  static const _bgColor = Color(0xFF121212);
  static const _appBarColor = Color(0xFF1F1F1F);
  static const _cardColor = Color(0xFF1E1E1E);
  static const _accent = Color(0xFF69F0AE); // greenAccent.shade400

  // 🔹 AppBar + Search Field Theme
  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: _bgColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: _appBarColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.grey),
        border: InputBorder.none,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  // ❌ Clear button
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => query = '',
        ),
    ];
  }

  // ⬅ Back button
  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildContent();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildContent();
  }

  // 🔹 Shared UI for results & suggestions
  Widget _buildContent() {
    final filtered = data
        .where((e) => e.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (query.isEmpty) {
      return _emptyState(
        icon: Icons.search,
        text: 'Search users, status or calls',
      );
    }

    if (filtered.isEmpty) {
      return _emptyState(
        icon: Icons.search_off,
        text: 'No matching results',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = filtered[index];

        return Material(
          color: _cardColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => close(context, item),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: _accent,
                    child: Text(
                      item[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 🔹 Empty / Info State
  Widget _emptyState({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey, size: 64),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
