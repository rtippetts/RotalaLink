import 'package:flutter/material.dart';

class StepBar extends StatelessWidget {
  const StepBar({
    super.key,
    required this.total,
    required this.current, // 1-based: step 1..total
    this.height = 4,
    this.gap = 6,
    this.radius = 999,
  });

  final int total;
  final int current; // 1..total
  final double height;
  final double gap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = current.clamp(1, total);

    return Semantics(
      label: 'Step $cur of $total',
      value: '$cur/$total',
      child: Row(
        children: List.generate(total, (i) {
          final stepIndex = i + 1;
          final isFilled = stepIndex <= cur;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: i == 0 || i == total - 1 ? 0 : gap / 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: height,
                decoration: BoxDecoration(
                  color: isFilled ? cs.primary : cs.outline.withOpacity(.35),
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
