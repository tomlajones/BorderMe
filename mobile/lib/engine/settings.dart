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
  black('black', 'Black', 0xFF000000);

  const BorderColour(this.wire, this.label, this.argb);
  final String wire;
  final String label;
  final int argb;

  static BorderColour fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => BorderColour.white);
}

enum SizePreset {
  instagramPortrait('instagram-portrait', '4:5 Portrait'),
  instagramTall('instagram-tall', '3:4 Tall'),
  instagramLandscape('instagram-landscape', '1.91:1 Landscape'),
  square('square', '1:1 Square'),
  original('original', 'Original');

  const SizePreset(this.wire, this.label);
  final String wire;
  final String label;

  static SizePreset fromWire(String? value) =>
      values.firstWhere((e) => e.wire == value, orElse: () => SizePreset.instagramPortrait);
}

class RenderSettings {
  const RenderSettings({required this.border, required this.colour, required this.size});

  static const standard =
      RenderSettings(border: BorderSize.medium, colour: BorderColour.white, size: SizePreset.instagramPortrait);

  final BorderSize border;
  final BorderColour colour;
  final SizePreset size;

  factory RenderSettings.fromMap(Map<Object?, Object?>? map) => RenderSettings(
        border: BorderSize.fromWire(map?['border'] as String?),
        colour: BorderColour.fromWire(map?['colour'] as String?),
        size: SizePreset.fromWire(map?['size'] as String?),
      );

  Map<String, String> toMap() => {'border': border.wire, 'colour': colour.wire, 'size': size.wire};

  RenderSettings copyWith({BorderSize? border, BorderColour? colour, SizePreset? size}) => RenderSettings(
        border: border ?? this.border,
        colour: colour ?? this.colour,
        size: size ?? this.size,
      );

  @override
  bool operator ==(Object other) =>
      other is RenderSettings && other.border == border && other.colour == colour && other.size == size;

  @override
  int get hashCode => Object.hash(border, colour, size);
}
