import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/engine_client.dart';
import '../state/session_controller.dart';

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final textTheme = Theme.of(context).textTheme;

    if (c.permissionDenied) {
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Mat Board needs permission to add photos',
                        style: textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Your photos weren't saved. Allow Mat Board to add photos in Settings, then try again. "
                        'It only ever adds new copies; it never reads or changes your library.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: c.openSettings,
                        child: const Text('Open Settings'),
                      ),
                      TextButton(
                        onPressed: c.backToEditing,
                        child: const Text('Back to photos'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              c.saveError != null
                  ? 'Saving stopped'
                  : (c.saved == 1
                        ? 'Saved 1 photo'
                        : 'Saved ${c.saved} photos'),
              style: textTheme.headlineSmall,
            ),
            if (c.saveError != null) ...[
              const SizedBox(height: 8),
              Text(c.saveError!),
            ],
            if (c.stopReason case final reason?) ...[
              const SizedBox(height: 8),
              Text(switch (reason) {
                StopReason.lowMemory =>
                  'Your iPhone ran low on memory, so Mat Board stopped after ${c.saved} of ${c.total}. '
                      'Try the rest in a smaller batch.',
                StopReason.outOfTime =>
                  'Mat Board stopped after ${c.saved} of ${c.total} because it was in the background. '
                      'Keep Mat Board open while it saves, then try the rest again.',
              }),
            ],
            if (c.thumbnails.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: c.thumbnails.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Image.file(
                    File(c.thumbnails[i]),
                    height: 120,
                    errorBuilder: (_, _, _) =>
                        Container(width: 96, color: Colors.black12),
                  ),
                ),
              ),
            ],
            if (c.skipped.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Skipped', style: textTheme.titleMedium),
              for (final s in c.skipped)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Photo ${s.index + 1}: ${s.reason}'),
                ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('open-photos'),
              onPressed: c.openPhotos,
              child: const Text('Open Photos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('start-again'),
              onPressed: c.startAgain,
              child: const Text('Start again'),
            ),
          ],
        ),
      ),
    );
  }
}
