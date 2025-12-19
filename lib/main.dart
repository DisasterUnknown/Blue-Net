import 'package:bluetooth_chat_app/services/bluetooth_turn_on_service.dart';
import 'package:bluetooth_chat_app/data/permission/permission_handler_service.dart';
import 'package:bluetooth_chat_app/ui/home_page/home_page.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BluetoothController.turnOnBluetooth();
  await PermissionHandlerService.requestBluetoothPermissions();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MaterialApp(
        title: 'Blue Chat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
