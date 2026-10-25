import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire values match the Swift engine', () {
    expect(BorderSize.values.map((e) => e.wire), ['small', 'medium', 'large']);
    expect(BorderColour.values.map((e) => e.wire), ['white', 'off-white', 'light-grey', 'black']);
    expect(SizePreset.values.map((e) => e.wire),
        ['instagram-portrait', 'instagram-tall', 'instagram-landscape', 'square', 'original']);
  });

  test('settings round-trip through a channel map', () {
    const settings = RenderSettings(border: BorderSize.large, colour: BorderColour.offWhite, size: SizePreset.square);
    expect(settings.toMap(), {'border': 'large', 'colour': 'off-white', 'size': 'square'});
    expect(RenderSettings.fromMap(settings.toMap()), settings);
  });

  test('missing or unknown values fall back to the defaults', () {
    expect(RenderSettings.fromMap(null), RenderSettings.standard);
    expect(RenderSettings.fromMap({'border': 'huge', 'size': 'square'}).border, BorderSize.medium);
    expect(RenderSettings.standard,
        const RenderSettings(border: BorderSize.medium, colour: BorderColour.white, size: SizePreset.instagramPortrait));
  });

  test('colour swatches match the engine colours', () {
    expect(BorderColour.offWhite.argb, 0xFFFAF7F0);
    expect(BorderColour.lightGrey.argb, 0xFFE6E6E6);
  });

  test('batch events parse from native maps', () {
    expect(parseBatchEvent({'type': 'saved', 'index': 1, 'thumbnail': '/t.jpg'}),
        const PhotoSaved(index: 1, thumbnailPath: '/t.jpg'));
    expect(parseBatchEvent({'type': 'skipped', 'index': 2, 'reason': 'not a readable image file'}),
        const PhotoSkipped(index: 2, reason: 'not a readable image file'));
    expect(parseBatchEvent({'type': 'stopped', 'saved': 3, 'total': 9}), const BatchStopped(saved: 3, total: 9));
    expect(parseBatchEvent({'type': 'finished', 'saved': 9, 'total': 9}), const BatchFinished(saved: 9, total: 9));
    expect(parseBatchEvent({'type': 'denied'}), const PermissionDenied());
    expect(parseBatchEvent({'type': 'mystery'}), isNull);
    expect(parseBatchEvent('nonsense'), isNull);
  });
}
