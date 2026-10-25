import 'dart:math' as math;
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
  late final PageController _pages = PageController(
    initialPage: widget.controller.currentIndex,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard these photos?'),
        content: const Text(
          "Nothing has been saved yet, so you'll need to choose them again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) widget.controller.startAgain();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final count = c.photos.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Start again',
          onPressed: _confirmDiscard,
        ),
        title: Text(count == 1 ? '1 photo' : '${c.currentIndex + 1} of $count'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            const saveHeight = 96.0;
            const minPreview = 140.0;
            final h = box.maxHeight;
            final room = h - saveHeight - minPreview;
            final panelMax = math.min(h * 0.45, room);
            final compact = panelMax < 96;
            final pager = PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: c.showPhoto,
              itemBuilder: (context, i) => _Preview(
                bytes: c.previews[i],
                error: i == c.currentIndex ? c.previewError : null,
                stale: c.previews[i] != null && !c.isPreviewCurrent(i),
                label: 'Preview of photo ${i + 1} of $count',
              ),
            );
            final panel = Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SettingsPanel(
                settings: c.settings,
                onChanged: c.updateSettings,
              ),
            );
            return Column(
              children: [
                Expanded(
                  child: compact
                      ? SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: minPreview, child: pager),
                              panel,
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(child: pager),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: panelMax),
                              child: SingleChildScrollView(child: panel),
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('save'),
                      onPressed: c.save,
                      child: Text(
                        count == 1 ? 'Save 1 photo' : 'Save $count photos',
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.bytes,
    required this.error,
    required this.stale,
    required this.label,
  });

  final Uint8List? bytes;
  final String? error;

  /// The image shown was rendered with older settings.
  final bool stale;
  final String label;

  @override
  Widget build(BuildContext context) {
    final image = bytes;
    final Widget content;
    if (image != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: stale ? 0.5 : 1,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(blurRadius: 12, color: Color(0x33000000)),
                      ],
                    ),
                    child: Image.memory(
                      image,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                if (stale && error == null) const CircularProgressIndicator(),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
          ],
        ],
      );
    } else if (error != null) {
      content = Text(error!, textAlign: TextAlign.center);
    } else {
      content = const CircularProgressIndicator();
    }
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: content),
      ),
    );
  }
}
