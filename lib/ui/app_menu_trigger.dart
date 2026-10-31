import 'package:flutter/material.dart';

/// A compact menu trigger for page headings. Form fields use AppDropdownField.
class AppMenuTrigger extends StatelessWidget {
  const AppMenuTrigger({
    super.key,
    required this.label,
    required this.isOpen,
    required this.onPressed,
    this.semanticsLabel,
    this.textStyle,
    this.foregroundColor,
  });

  final String label;
  final bool isOpen;
  final VoidCallback? onPressed;
  final String? semanticsLabel;
  final TextStyle? textStyle;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticsLabel,
      expanded: isOpen,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: isOpen
              ? scheme.onPrimaryContainer
              : foregroundColor ?? scheme.onSurfaceVariant,
          backgroundColor: isOpen
              ? scheme.primaryContainer
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          textStyle: textStyle ?? Theme.of(context).textTheme.bodyMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            AppMenuArrow(isOpen: isOpen),
          ],
        ),
      ),
    );
  }
}

class AppMenuArrow extends StatelessWidget {
  const AppMenuArrow({super.key, required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: isOpen ? .5 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Durations.short3,
    curve: Curves.easeInOutCubic,
    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
  );
}
