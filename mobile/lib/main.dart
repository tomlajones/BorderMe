import 'package:flutter/material.dart';

import 'engine/engine_client.dart';
import 'screens/home_page.dart';
import 'state/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SessionController(MethodChannelEngine());
  controller.init();
  runApp(BorderMeApp(controller: controller));
}

class BorderMeApp extends StatelessWidget {
  const BorderMeApp({super.key, required this.controller});

  final SessionController controller;

  static const _seed = Color(0xFF3D5A80);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BorderMe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(controller: controller),
    );
  }
}
