import 'package:bluetooth_chat_app/services/bluetooth_turn_on_service.dart';
import 'package:bluetooth_chat_app/data/permission/permission_handler_service.dart';
import 'package:bluetooth_chat_app/services/routing_service.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.init();
  await BluetoothController.turnOnBluetooth();
  await PermissionHandlerService.requestBluetoothPermissions();
  await MeshService.instance.start();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final routing = RoutingService();

    return SafeArea(
      child: MaterialApp(
        title: 'Blue Chat',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        debugShowCheckedModeBanner: false,
        navigatorKey: routing.navigatorKey,
        initialRoute: RoutingService.home,
        onGenerateRoute: routing.onGenerateRoute,
      ),
    );
  }
}
