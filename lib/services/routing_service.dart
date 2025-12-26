import 'package:bluetooth_chat_app/ui/chat_page/chat_page.dart';
import 'package:bluetooth_chat_app/ui/home_page/home_page.dart';
import 'package:bluetooth_chat_app/ui/info_page/info_page.dart';
import 'package:flutter/material.dart';

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const String home = '/';
  static const String infoPage = '/info-page';
  static const String chatPage = '/chat-page';

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => HomePage());

      case infoPage:
        return MaterialPageRoute(builder: (_) => InfoPage());

      case chatPage:
        final args = settings.arguments as ChatPage;

        return MaterialPageRoute(
          builder: (_) =>
              ChatPage(userName: args.userName, userId: args.userId),
        );
    }
    return null;
  }

  Future<dynamic>? navigateWithSlide(
    Widget page, {
    Offset begin = const Offset(1.0, 0.0),
    Curve curve = Curves.ease,
  }) {
    return navigatorKey.currentState?.push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) {
          final tween = Tween(
            begin: begin,
            end: Offset.zero,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  Future<dynamic>? navigateTo(String routeName, {Object? arguments}) {
    return navigatorKey.currentState?.pushNamed(
      routeName,
      arguments: arguments,
    );
  }

  void goBack() {
    navigatorKey.currentState?.pop();
  }
}
