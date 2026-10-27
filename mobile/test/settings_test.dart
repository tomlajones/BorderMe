import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire values match the Swift engine', () {
    expect(BorderSize.values.map((e) => e.wire), ['small', 'medium', 'large']);
    expect(BorderColour.values.map((e) => e.wire), ['white', 'off-white', 'light-grey', 'black', 'custom']);
    expect(Shape.values.map((e) => e.wire), ['5:4', '4:3', '3:2', '16:9', '1:1', '1.91:1', 'custom', 'original']);
    expect(CanvasOrientation.values.map((e) => e.wire), ['portrait', 'landscape']);
  });

  test('settings round-trip through a channel map', () {
    const settings = RenderSettings(
      border: BorderSize.large,
      colour: BorderColour.custom,
      shape: Shape.custom,
      orientation: CanvasOrientation.landscape,
      customColour: '#336699',
      customWidth: 2.35,
      customHeight: 1,
    );
    expect(settings.toMap(), {
      'border': 'large',
      'colour': 'custom',
      'shape': 'custom',
      'orientation': 'landscape',
      'customColour': '#336699',
      'customWidth': 2.35,
      'customHeight': 1.0,
    });
    expect(RenderSettings.fromMap(settings.toMap()), settings);
    expect(RenderSettings.fromMap({'customWidth': 7, 'customHeight': 5}).customWidth, 7.0);
  });

  test('missing or unknown values fall back to the defaults', () {
    expect(RenderSettings.fromMap(null), RenderSettings.standard);
    expect(RenderSettings.fromMap({'border': 'huge', 'shape': '1:1'}).border, BorderSize.medium);
    expect(RenderSettings.fromMap({'customColour': 'blue'}).customColour, RenderSettings.defaultCustomColour);
    expect(RenderSettings.standard,
        const RenderSettings(border: BorderSize.medium, colour: BorderColour.white, shape: Shape.fiveFour));
    expect(RenderSettings.standard.ratioLabel, '4:5');
  });

  test('shapes read the right way round and flag Instagram crops', () {
    RenderSettings s(Shape shape, [CanvasOrientation o = CanvasOrientation.portrait]) =>
        RenderSettings(border: BorderSize.medium, colour: BorderColour.white, shape: shape, orientation: o);
    const landscape = CanvasOrientation.landscape;
    expect(s(Shape.fiveFour).ratioLabel, '4:5');
    expect(s(Shape.fiveFour, landscape).ratioLabel, '5:4');
    expect(s(Shape.threeTwo).ratioLabel, '2:3');
    expect(s(Shape.sixteenNine, landscape).ratioLabel, '16:9');
    expect(s(Shape.instagramWide).ratioLabel, '1.91:1');
    expect(s(Shape.square, landscape).ratioLabel, '1:1');
    expect(s(Shape.original).ratioLabel, 'Original');

    expect(s(Shape.fiveFour).instagramCrops, isFalse);
    expect(s(Shape.fourThree).instagramCrops, isFalse);
    expect(s(Shape.threeTwo).instagramCrops, isTrue);
    expect(s(Shape.threeTwo, landscape).instagramCrops, isFalse);
    expect(s(Shape.sixteenNine).instagramCrops, isTrue);
    expect(s(Shape.instagramWide).instagramCrops, isFalse);
    expect(s(Shape.original).instagramCrops, isFalse);
    expect(s(Shape.custom).copyWith(customWidth: 2.35, customHeight: 1).instagramCrops, isTrue);
    expect(s(Shape.custom).copyWith(customWidth: 10, customHeight: 1).aspect, 3);
  });

  test('hex colours parse and fill the border', () {
    expect(parseHexColour('#336699'), 0x336699);
    expect(parseHexColour('336699'), 0x336699);
    expect(parseHexColour('£336699'), 0x336699);
    expect(parseHexColour('#3366'), isNull);
    expect(parseHexColour('#GGGGGG'), isNull);
    expect(hexColour(0x0a0b0c), '#0A0B0C');
    const custom = RenderSettings(
        border: BorderSize.medium, colour: BorderColour.custom, shape: Shape.square, customColour: '#336699');
    expect(custom.fillArgb, 0xFF336699);
    expect(custom.copyWith(colour: BorderColour.black).fillArgb, 0xFF000000);
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
    expect(parseBatchEvent({'type': 'stopped', 'saved': 3, 'total': 9, 'reason': 'memory'}),
        const BatchStopped(saved: 3, total: 9, reason: StopReason.lowMemory));
    expect(parseBatchEvent({'type': 'stopped', 'saved': 3, 'total': 9, 'reason': 'time'}),
        const BatchStopped(saved: 3, total: 9, reason: StopReason.outOfTime));
    expect(parseBatchEvent({'type': 'finished', 'saved': 9, 'total': 9}), const BatchFinished(saved: 9, total: 9));
    expect(parseBatchEvent({'type': 'denied'}), const PermissionDenied());
    expect(parseBatchEvent({'type': 'mystery'}), isNull);
    expect(parseBatchEvent('nonsense'), isNull);
  });
}
