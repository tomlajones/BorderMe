import 'package:flutter/material.dart';

import '../engine/settings.dart';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final RenderSettings settings;
  final ValueChanged<RenderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
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
                colour: c,
                selected: c == settings.colour,
                onTap: () => onChanged(settings.copyWith(colour: c)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Size', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in SizePreset.values)
              ChoiceChip(
                label: Text(s.label),
                selected: s == settings.size,
                onSelected: (_) => onChanged(settings.copyWith(size: s)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final BorderColour colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: colour.label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkResponse(
          key: Key('colour-${colour.wire}'),
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
                  color: Color(colour.argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
