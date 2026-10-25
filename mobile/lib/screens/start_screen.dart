import 'package:flutter/material.dart';

import '../state/session_controller.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final failed = controller.failedToLoad;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('BorderMe', style: textTheme.displaySmall),
                      const SizedBox(height: 12),
                      Text(
                        'Clean borders for your photos, with nothing cropped.',
                        style: textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick up to ${SessionController.maxPhotos} photos.',
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        key: const Key('choose'),
                        onPressed: controller.choosePhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photos'),
                      ),
                      if (failed > 0) ...[
                        const SizedBox(height: 16),
                        Text(
                          failed == 1
                              ? "1 photo couldn't be loaded."
                              : "$failed photos couldn't be loaded.",
                          style: textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
