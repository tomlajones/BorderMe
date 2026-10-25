import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../state/session_controller.dart';
import 'settings_panel.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final PageController _pages = PageController(initialPage: widget.controller.currentIndex);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final count = c.photos.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Start again', onPressed: c.startAgain),
        title: Text(count == 1 ? '1 photo' : '${c.currentIndex + 1} of $count'),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: c.showPhoto,
              itemBuilder: (context, i) => _Preview(
                bytes: c.previews[i],
                error: i == c.currentIndex ? c.previewError : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SettingsPanel(settings: c.settings, onChanged: c.updateSettings),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save'),
                onPressed: c.save,
                child: Text(count == 1 ? 'Save 1 photo' : 'Save $count photos'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.bytes, required this.error});

  final Uint8List? bytes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: image != null
            ? DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(blurRadius: 12, color: Color(0x33000000))]),
                child: Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
              )
            : error != null
                ? Text(error!, textAlign: TextAlign.center)
                : const CircularProgressIndicator(),
      ),
    );
  }
}
