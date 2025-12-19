import 'package:flutter/material.dart';

Widget buildStatusList() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orangeAccent,
          child: Text('S$index', style: const TextStyle(color: Colors.black)),
        ),
        title: Text(
          'Status $index',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          'Today, 12:0$index PM',
          style: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }