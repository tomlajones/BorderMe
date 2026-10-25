import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:borderme/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('init loads the last-used settings', () async {
    const stored = RenderSettings(border: BorderSize.large, colour: BorderColour.black, size: SizePreset.square);
    final controller = SessionController(FakeEngine(stored: stored), debounce: Duration.zero);
    await controller.init();
    expect(controller.settings, stored);
  });

  test('choosing photos opens the editor and previews the first photo', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    await settle();
    expect(controller.phase, Phase.editing);
    expect(controller.photos, ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(engine.previewRequests.single.$1, '/tmp/a.jpg');
    expect(controller.previews[0], isNotNull);
  });

  test('the loading screen shows while picked photos copy', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: Duration.zero);
    engine.announceLoading(2);
    await settle();
    expect(controller.phase, Phase.loading);
  });

  test('a pick where nothing loads returns to the start and counts failures', () async {
    final engine = FakeEngine(pickResult: const PickResult(paths: [], failed: 3));
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    expect(controller.phase, Phase.start);
    expect(controller.failedToLoad, 3);
  });

  test('a busy picker is ignored without changing the phase', () async {
    final engine = FakeEngine()..busyPick = true;
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    expect(controller.phase, Phase.start);
    expect(controller.photos, isEmpty);
  });

  test('rapid setting changes save each time but preview once', () async {
    final engine = FakeEngine();
    final controller = SessionController(engine, debounce: const Duration(milliseconds: 50));
    await controller.choosePhotos();
    await settle();
    engine.previewRequests.clear();

    controller.updateSettings(controller.settings.copyWith(colour: BorderColour.black));
    controller.updateSettings(controller.settings.copyWith(size: SizePreset.instagramTall));
    controller.updateSettings(controller.settings.copyWith(border: BorderSize.large));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(engine.savedSettings, hasLength(3));
    expect(engine.previewRequests, hasLength(1));
    expect(engine.previewRequests.single.$2,
        const RenderSettings(border: BorderSize.large, colour: BorderColour.black, size: SizePreset.instagramTall));
  });

  test('a preview failure is shown on the current photo', () async {
    final controller = SessionController(FakeEngine(failPreview: true), debounce: Duration.zero);
    await controller.choosePhotos();
    await settle();
    expect(controller.previewError, isNotNull);
  });

  test('saving collects saved and skipped photos, then finishes', () async {
    final engine = FakeEngine(events: const [
      PhotoSaved(index: 0, thumbnailPath: '/tmp/t0.jpg'),
      PhotoSkipped(index: 1, reason: 'not a readable image file'),
      BatchFinished(saved: 1, total: 2),
    ]);
    final controller = SessionController(engine, debounce: Duration.zero);
    await controller.choosePhotos();
    await controller.save();
    expect(engine.processedPaths, ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(controller.phase, Phase.done);
    expect(controller.saved, 1);
    expect(controller.thumbnails, ['/tmp/t0.jpg']);
    expect(controller.skipped.single.reason, 'not a readable image file');
    expect(controller.stoppedLowMemory, isFalse);
  });

  test('low memory and refused permission are reported', () async {
    final lowMemory = SessionController(
      FakeEngine(events: const [PhotoSaved(index: 0, thumbnailPath: ''), BatchStopped(saved: 1, total: 2)]),
      debounce: Duration.zero,
    );
    await lowMemory.choosePhotos();
    await lowMemory.save();
    expect(lowMemory.stoppedLowMemory, isTrue);
    expect(lowMemory.thumbnails, isEmpty);

    final denied = SessionController(FakeEngine(events: const [PermissionDenied()]), debounce: Duration.zero);
    await denied.choosePhotos();
    await denied.save();
    expect(denied.permissionDenied, isTrue);
    expect(denied.phase, Phase.done);
  });

  test('start again clears the session', () async {
    final controller = SessionController(FakeEngine(), debounce: Duration.zero);
    await controller.choosePhotos();
    controller.startAgain();
    expect(controller.phase, Phase.start);
    expect(controller.photos, isEmpty);
    expect(controller.previews, isEmpty);
  });
}
