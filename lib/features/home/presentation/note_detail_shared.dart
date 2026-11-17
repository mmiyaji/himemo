import 'package:flutter/material.dart';

/// A data-agnostic tag chip shared by the V1 note detail and V2 preview.
///
/// Callers provide the display label and action so this widget never reads
/// note state, providers, or storage itself.
class NoteDetailTagChip extends StatelessWidget {
  const NoteDetailTagChip({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final chipLabel = Text(
      label,
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (onPressed == null) {
      return Chip(
        label: chipLabel,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        side: BorderSide(color: Theme.of(context).dividerColor),
      );
    }
    return ActionChip(
      label: chipLabel,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }
}
