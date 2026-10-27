import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/settings.dart';
import 'colour_picker_sheet.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final RenderSettings settings;
  final ValueChanged<RenderSettings> onChanged;

  Future<void> _pickCustomColour(BuildContext context) async {
    final picked = await showColourPicker(context, initial: settings.customColour);
    if (picked == null) return;
    onChanged(settings.copyWith(colour: BorderColour.custom, customColour: picked));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Border', style: labelStyle),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<BorderSize>(
            showSelectedIcon: false,
            segments: [
              for (final b in BorderSize.values)
                ButtonSegment(value: b, label: Text(b.label)),
            ],
            selected: {settings.border},
            onSelectionChanged: (s) =>
                onChanged(settings.copyWith(border: s.first)),
          ),
        ),
        const SizedBox(height: 16),
        Text('Colour', style: labelStyle),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final c in BorderColour.values)
              _Swatch(
                key: Key('colour-${c.wire}'),
                label: c == BorderColour.custom
                    ? 'Custom colour, ${settings.customColour}'
                    : c.label,
                argb: c.argb ??
                    settings.copyWith(colour: BorderColour.custom).fillArgb,
                selected: c == settings.colour,
                editable: c == BorderColour.custom,
                onTap: c == BorderColour.custom
                    ? () => _pickCustomColour(context)
                    : () => onChanged(settings.copyWith(colour: c)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Size', style: labelStyle),
        const SizedBox(height: 6),
        // One swipeable row keeps the panel short; the next chip peeking in
        // at the edge shows there's more.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final s in Shape.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('shape-${s.wire}'),
                    label: Text(_chipLabel(s)),
                    selected: s == settings.shape,
                    onSelected: (_) => onChanged(settings.copyWith(shape: s)),
                  ),
                ),
            ],
          ),
        ),
        if (settings.shape.hasOrientation) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<CanvasOrientation>(
              showSelectedIcon: false,
              segments: [
                for (final o in CanvasOrientation.values)
                  ButtonSegment(
                    value: o,
                    label: Text(o.label, key: Key('orientation-${o.wire}')),
                  ),
              ],
              selected: {settings.orientation},
              onSelectionChanged: (o) =>
                  onChanged(settings.copyWith(orientation: o.first)),
            ),
          ),
        ],
        if (settings.shape == Shape.custom) ...[
          const SizedBox(height: 12),
          _CustomRatioFields(settings: settings, onChanged: onChanged),
        ],
        if (settings.instagramCrops) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Instagram's feed will crop this shape. It takes anything from 3:4 tall to 1.91:1 wide.",
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _chipLabel(Shape shape) {
    final asShown = settings.copyWith(shape: shape);
    return switch (shape) {
      Shape.original => 'Original',
      Shape.custom => settings.shape == Shape.custom
          ? 'Custom ${settings.ratioLabel}'
          : 'Custom',
      _ => '${asShown.ratioLabel} ${_purpose(shape, settings.orientation)}',
    };
  }

  static String _purpose(Shape shape, CanvasOrientation orientation) {
    final portrait = orientation == CanvasOrientation.portrait;
    return switch (shape) {
      Shape.fiveFour => portrait ? 'Instagram' : 'Print',
      Shape.fourThree => portrait ? 'Instagram tall' : 'iPhone',
      Shape.threeTwo => 'Camera',
      Shape.sixteenNine => portrait ? 'Stories' : 'Widescreen',
      Shape.square => 'Square',
      Shape.instagramWide => 'Instagram widest',
      Shape.custom || Shape.original => '',
    };
  }
}

/// Width and height boxes for a custom ratio. They keep their own text while
/// someone is typing, and only send a ratio on once it makes sense.
class _CustomRatioFields extends StatefulWidget {
  const _CustomRatioFields({required this.settings, required this.onChanged});

  final RenderSettings settings;
  final ValueChanged<RenderSettings> onChanged;

  @override
  State<_CustomRatioFields> createState() => _CustomRatioFieldsState();
}

class _CustomRatioFieldsState extends State<_CustomRatioFields> {
  late final TextEditingController _width =
      TextEditingController(text: _format(widget.settings.customWidth));
  late final TextEditingController _height =
      TextEditingController(text: _format(widget.settings.customHeight));
  String? _error;

  static String _format(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  static double? _parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value > 100) return null;
    return value;
  }

  void _changed() {
    final width = _parse(_width.text);
    final height = _parse(_height.text);
    if (width == null || height == null) {
      setState(() => _error = 'Use numbers above 0 and up to 100.');
      return;
    }
    final aspect = width / height;
    setState(() {
      _error = aspect > customMaximumAspect || aspect < 1 / customMaximumAspect
          ? 'Custom shapes go from 1:3 to 3:1, so this is kept at the nearest.'
          : null;
    });
    widget.onChanged(widget.settings.copyWith(customWidth: width, customHeight: height));
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, Key key) => SizedBox(
        width: 96,
        child: TextField(
          key: key,
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,2})?$')),
          ],
          textAlign: TextAlign.center,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: (_) => _changed(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _field(_width, 'Width', const Key('custom-width')),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: TextStyle(fontSize: 20)),
            ),
            _field(_height, 'Height', const Key('custom-height')),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.label,
    required this.argb,
    required this.selected,
    required this.editable,
    required this.onTap,
  });

  final String label;
  final int argb;
  final bool selected;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = Color(argb);
    final onFill = fill.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: label,
        hint: editable ? 'Opens the colour picker' : null,
        onTap: onTap,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: editable ? Icon(Icons.colorize, size: 18, color: onFill) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
