/// Mirrors BorderEngine's Settings.swift. The wire values are the contract
/// with native code and must not change.
enum BorderSize {
  small('small', 'Small'),
  medium('medium', 'Medium'),
  large('large', 'Large');

  const BorderSize(this.wire, this.label);
  final String wire;
  final String label;

  static BorderSize fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => BorderSize.medium);
}

enum BorderColour {
  white('white', 'White', 0xFFFFFFFF),
  offWhite('off-white', 'Off-white', 0xFFFAF7F0),
  lightGrey('light-grey', 'Light grey', 0xFFE6E6E6),
  black('black', 'Black', 0xFF000000),

  /// The colour the person picked, kept in [RenderSettings.customColour].
  custom('custom', 'Custom', null);

  const BorderColour(this.wire, this.label, this.argb);
  final String wire;
  final String label;
  final int? argb;

  static BorderColour fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => BorderColour.white);
}

/// The canvas shape. Shapes with an orientation are named long side first
/// and turned on their side for portrait, so 5:4 in portrait is Instagram's
/// 4:5.
enum Shape {
  fiveFour('5:4', 5, 4),
  fourThree('4:3', 4, 3),
  threeTwo('3:2', 3, 2),
  sixteenNine('16:9', 16, 9),
  square('1:1', 1, 1),
  instagramWide('1.91:1', 1.91, 1),
  custom('custom', 0, 0),
  original('original', 0, 0);

  const Shape(this.wire, this.long, this.short);
  final String wire;
  final double long;
  final double short;

  /// Square has no sides to swap, and 1.91:1 only exists as a landscape
  /// Instagram shape. A custom ratio is typed in the way round it's wanted.
  bool get hasOrientation => switch (this) {
        fiveFour || fourThree || threeTwo || sixteenNine => true,
        _ => false,
      };

  static Shape fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => Shape.fiveFour);
}

enum CanvasOrientation {
  portrait('portrait', 'Portrait'),
  landscape('landscape', 'Landscape');

  const CanvasOrientation(this.wire, this.label);
  final String wire;
  final String label;

  static CanvasOrientation fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => CanvasOrientation.portrait);
}

/// Instagram's feed takes anything from 3:4 tall to 1.91:1 wide.
const instagramTallest = 3 / 4;
const instagramWidest = 1.91;

/// Matches CustomRatio.maximumAspect in the engine.
const customMaximumAspect = 3.0;

/// Reads "#RRGGBB" as 0xRRGGBB, or null. The # is optional, and any other
/// symbol in its place is ignored too: a UK keyboard puts £ where # would be.
int? parseHexColour(String text) {
  var digits = text.trim();
  if (digits.isNotEmpty && !RegExp(r'[0-9a-zA-Z]').hasMatch(digits[0])) digits = digits.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(digits)) return null;
  return int.parse(digits, radix: 16);
}

String hexColour(int rgb) => '#${(rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _number(double value) {
  final text = value.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

class RenderSettings {
  const RenderSettings({
    required this.border,
    required this.colour,
    required this.shape,
    this.orientation = CanvasOrientation.portrait,
    this.customColour = defaultCustomColour,
    this.customWidth = 7,
    this.customHeight = 5,
  });

  static const defaultCustomColour = '#F4F1EA';

  static const standard = RenderSettings(border: BorderSize.medium, colour: BorderColour.white, shape: Shape.fiveFour);

  final BorderSize border;
  final BorderColour colour;
  final Shape shape;
  final CanvasOrientation orientation;

  /// "#RRGGBB", used when [colour] is custom.
  final String customColour;
  final double customWidth;
  final double customHeight;

  /// The border fill as an opaque ARGB value.
  int get fillArgb =>
      colour.argb ?? (0xFF000000 | (parseHexColour(customColour) ?? parseHexColour(defaultCustomColour)!));

  /// Width over height, or null for Original, which keeps the photo's shape.
  double? get aspect {
    switch (shape) {
      case Shape.original:
        return null;
      case Shape.custom:
        if (customWidth <= 0 || customHeight <= 0) return 4 / 5;
        return (customWidth / customHeight).clamp(1 / customMaximumAspect, customMaximumAspect);
      default:
        final landscape = shape.long / shape.short;
        return shape.hasOrientation && orientation == CanvasOrientation.portrait ? 1 / landscape : landscape;
    }
  }

  /// The shape as people say it, the right way round: "4:5", "16:9".
  String get ratioLabel {
    switch (shape) {
      case Shape.original:
        return 'Original';
      case Shape.custom:
        return '${_number(customWidth)}:${_number(customHeight)}';
      default:
        final long = _number(shape.long);
        final short = _number(shape.short);
        return shape.hasOrientation && orientation == CanvasOrientation.portrait ? '$short:$long' : '$long:$short';
    }
  }

  /// True when Instagram's feed would crop this canvas.
  bool get instagramCrops {
    final a = aspect;
    return a != null && (a < instagramTallest - 1e-9 || a > instagramWidest + 1e-9);
  }

  factory RenderSettings.fromMap(Map<Object?, Object?>? map) {
    double number(String key, double fallback) => (map?[key] as num?)?.toDouble() ?? fallback;
    final hex = map?['customColour'] as String?;
    return RenderSettings(
      border: BorderSize.fromWire(map?['border'] as String?),
      colour: BorderColour.fromWire(map?['colour'] as String?),
      shape: Shape.fromWire(map?['shape'] as String?),
      orientation: CanvasOrientation.fromWire(map?['orientation'] as String?),
      customColour: hex != null && parseHexColour(hex) != null ? hex : defaultCustomColour,
      customWidth: number('customWidth', 7),
      customHeight: number('customHeight', 5),
    );
  }

  Map<String, Object> toMap() => {
        'border': border.wire,
        'colour': colour.wire,
        'shape': shape.wire,
        'orientation': orientation.wire,
        'customColour': customColour,
        'customWidth': customWidth,
        'customHeight': customHeight,
      };

  RenderSettings copyWith({
    BorderSize? border,
    BorderColour? colour,
    Shape? shape,
    CanvasOrientation? orientation,
    String? customColour,
    double? customWidth,
    double? customHeight,
  }) =>
      RenderSettings(
        border: border ?? this.border,
        colour: colour ?? this.colour,
        shape: shape ?? this.shape,
        orientation: orientation ?? this.orientation,
        customColour: customColour ?? this.customColour,
        customWidth: customWidth ?? this.customWidth,
        customHeight: customHeight ?? this.customHeight,
      );

  @override
  bool operator ==(Object other) =>
      other is RenderSettings &&
      other.border == border &&
      other.colour == colour &&
      other.shape == shape &&
      other.orientation == orientation &&
      other.customColour == customColour &&
      other.customWidth == customWidth &&
      other.customHeight == customHeight;

  @override
  int get hashCode => Object.hash(border, colour, shape, orientation, customColour, customWidth, customHeight);

  @override
  String toString() => 'RenderSettings(${toMap()})';
}
