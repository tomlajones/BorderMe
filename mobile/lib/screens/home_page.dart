import 'package:flutter/material.dart';

import '../state/session_controller.dart';
import 'done_screen.dart';
import 'edit_screen.dart';
import 'saving_screen.dart';
import 'start_screen.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.phase) {
        Phase.start => StartScreen(controller: controller),
        Phase.loading => const Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading photos…'),
              ]),
            ),
          ),
        Phase.editing => EditScreen(controller: controller),
        Phase.saving => SavingScreen(controller: controller),
        Phase.done => DoneScreen(controller: controller),
      },
    );
  }
}
