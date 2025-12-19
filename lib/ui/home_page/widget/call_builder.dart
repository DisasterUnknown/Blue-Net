import 'package:flutter/material.dart';

Widget buildCallList() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent,
          child: Text('C$index', style: const TextStyle(color: Colors.black)),
        ),
        title: Text(
          'Call User $index',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          'Yesterday, 1:0$index PM',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        trailing: const Icon(Icons.call, color: Colors.greenAccent),
      ),
    );
  }