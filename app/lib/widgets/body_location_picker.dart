import 'package:flutter/material.dart';
import '../theme/tokens.dart';

const _bodyRegions = [
  'Head',
  'Neck',
  'Chest',
  'Abdomen',
  'Upper back',
  'Lower back',
  'Left arm',
  'Right arm',
  'Left leg',
  'Right leg',
  'Pelvis / groin',
  'Generalized',
];

class BodyLocationPicker extends StatelessWidget {
  const BodyLocationPicker({
    super.key,
    required this.selectedLocation,
    required this.onChanged,
  });

  final String? selectedLocation;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where?',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Neutrals.slate),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s1,
          runSpacing: Space.s1,
          children: [
            for (final region in _bodyRegions)
              _RegionChip(
                label: region,
                selected: selectedLocation == region,
                onTap: () =>
                    onChanged(selectedLocation == region ? null : region),
              ),
          ],
        ),
      ],
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: BrandColors.concordBlue.withValues(alpha: 0.12),
      checkmarkColor: BrandColors.concordBlue,
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? BrandColors.concordBlue : Neutrals.slate,
      ),
      side: BorderSide(
        color: selected ? BrandColors.concordBlue : Neutrals.hairline,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 6),
    );
  }
}
