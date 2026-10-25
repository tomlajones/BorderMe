import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:borderme/main.dart';
import 'package:borderme/state/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

void main() {
  Future<FakeEngine> pumpApp(WidgetTester tester, {FakeEngine? engine}) async {
    final fake = engine ?? FakeEngine();
    final controller = SessionController(fake, debounce: Duration.zero);
    await tester.pumpWidget(BorderMeApp(controller: controller));
    return fake;
  }

  testWidgets('choose, restyle and save two photos', (tester) async {
    final engine = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    expect(find.text('Save 2 photos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('colour-black')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(engine.previewRequests.last.$2.colour, BorderColour.black);

    await tester.tap(find.text('3:4 Tall'));
    await tester.pumpAndSettle();
    expect(engine.savedSettings.last.size, SizePreset.instagramTall);

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(engine.processedSettings?.colour, BorderColour.black);
    expect(find.text('Saved 2 photos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-photos')));
    expect(engine.openedPhotos, 1);

    await tester.tap(find.byKey(const Key('start-again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('choose')), findsOneWidget);
  });

  testWidgets('skipped photos are listed with their reason', (tester) async {
    await pumpApp(tester, engine: FakeEngine(events: const [
      PhotoSaved(index: 0, thumbnailPath: ''),
      PhotoSkipped(index: 1, reason: 'not a readable image file'),
      BatchFinished(saved: 1, total: 2),
    ]));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved 1 photo'), findsOneWidget);
    expect(find.text('Photo 2: not a readable image file'), findsOneWidget);
  });

  testWidgets('refused permission explains and links to Settings', (tester) async {
    final engine = await pumpApp(tester, engine: FakeEngine(events: const [PermissionDenied()]));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission to add photos'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(engine.openedSettings, 1);
  });

  testWidgets('photos that failed to load are mentioned on the start screen', (tester) async {
    await pumpApp(tester, engine: FakeEngine(pickResult: const PickResult(paths: [], failed: 2)));
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    expect(find.textContaining("2 photos couldn't be loaded"), findsOneWidget);
  });

  testWidgets('a batch that fails part way shows the error on Done', (tester) async {
    await pumpApp(
      tester,
      engine: FakeEngine(
        events: const [PhotoSaved(index: 0, thumbnailPath: '')],
        streamError: PlatformException(code: 'x', message: 'event channel failed'),
      ),
    );
    await tester.tap(find.byKey(const Key('choose')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Something went wrong while saving'), findsOneWidget);
    expect(find.byKey(const Key('start-again')), findsOneWidget);
  });
}
