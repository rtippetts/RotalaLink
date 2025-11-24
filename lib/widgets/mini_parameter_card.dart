import 'package:flutter/material.dart';
import 'package:your_app/models/tank_models.dart';

class MiniParameterCard extends StatelessWidget {
  const MiniParameterCard({
    super.key,
    required this.reading,
    required this.color,
    required this.selected,
    this.showBadge = false,
  });

  final ParameterReading reading;
  final Color color;
  final bool selected;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : const Color(0xFF1f2937);
    final fg = selected ? Colors.white : color;
    final labelColor = Colors.white70;

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fg.withOpacity(0.9), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(_iconFor(reading.type), color: fg, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _label(reading.type),
                    style: TextStyle(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${reading.value % 1 == 0 ? reading.value.toInt() : reading.value.toStringAsFixed(reading.type == ParamType.ph ? 2 : 1)} ${reading.unit}',
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (showBadge)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFE74C3C),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _label(ParamType t) =>
      t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';

  static IconData _iconFor(ParamType t) => switch (t) {
        ParamType.temperature => Icons.thermostat,
        ParamType.ph => Icons.science,
        ParamType.tds => Icons.bubble_chart,
      };
}
