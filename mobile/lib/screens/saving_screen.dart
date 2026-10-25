import 'package:flutter/material.dart';

import '../state/session_controller.dart';

class SavingScreen extends StatelessWidget {
  const SavingScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.total;
    final current = (controller.processed + 1).clamp(1, total == 0 ? 1 : total);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Saving $current of $total', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: total == 0 ? 0 : controller.processed / total),
            ]),
          ),
        ),
      ),
    );
  }
}
