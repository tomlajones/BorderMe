import 'package:flutter/material.dart';

import '../engine/settings.dart';

/// Opens the colour picker and resolves to the chosen "#RRGGBB", or null if
/// it was dismissed.
Future<String?> showColourPicker(BuildContext context, {required String initial}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ColourPickerSheet(initial: initial),
    );

class ColourPickerSheet extends StatefulWidget {
  const ColourPickerSheet({super.key, required this.initial});

  final String initial;

  @override
  State<ColourPickerSheet> createState() => _ColourPickerSheetState();
}

class _ColourPickerSheetState extends State<ColourPickerSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    final rgb = parseHexColour(widget.initial) ?? parseHexColour(RenderSettings.defaultCustomColour)!;
    _hsv = HSVColor.fromColor(Color(0xFF000000 | rgb));
    _hex = TextEditingController(text: hexColour(rgb));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  int get _rgb => _hsv.toColor().toARGB32() & 0xFFFFFF;

  void _setHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexInvalid = false;
      _hex.text = hexColour(_rgb);
    });
  }

  void _typedHex(String text) {
    final rgb = parseHexColour(text);
    setState(() {
      _hexInvalid = rgb == null;
      if (rgb != null) _hsv = HSVColor.fromColor(Color(0xFF000000 | rgb));
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colour = _hsv.toColor();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Border colour', style: textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                key: const Key('picker-preview'),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  key: const Key('picker-hex'),
                  controller: _hex,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 7,
                  decoration: InputDecoration(
                    labelText: 'Hex',
                    counterText: '',
                    border: const OutlineInputBorder(),
                    errorText: _hexInvalid ? 'Six digits, like #F4F1EA' : null,
                  ),
                  onChanged: _typedHex,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GradientSlider(
            label: 'Hue',
            value: _hsv.hue / 360,
            colours: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
            onChanged: (v) => _setHsv(_hsv.withHue(v * 360)),
          ),
          _GradientSlider(
            label: 'Saturation',
            value: _hsv.saturation,
            colours: [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()],
            onChanged: (v) => _setHsv(_hsv.withSaturation(v)),
          ),
          _GradientSlider(
            label: 'Brightness',
            value: _hsv.value,
            colours: [Colors.black, _hsv.withValue(1).toColor()],
            onChanged: (v) => _setHsv(_hsv.withValue(v)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('picker-done'),
            onPressed: _hexInvalid ? null : () => Navigator.of(context).pop(hexColour(_rgb)),
            child: const Text('Use this colour'),
          ),
        ],
      ),
    );
  }
}

/// A slider drawn over a strip of the colours it moves between.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colours,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<Color> colours;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(colors: colours),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 12,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 3),
                ),
                child: Slider(
                  value: value.clamp(0, 1),
                  semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
