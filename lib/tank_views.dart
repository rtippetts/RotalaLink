import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../tank_detail_page.dart';
import '../app_settings.dart';
import '../tank_parameters.dart';

/// Shared label helper
String _labelForWaterType(String v) {
  switch (v) {
    case 'saltwater':
      return 'Saltwater';
    case 'brackish':
      return 'Brackish';
    default:
      return 'Freshwater';
  }
}

class TankCard extends StatelessWidget {
  const TankCard({
    super.key,
    required this.row,
    required this.onOpen,
    required this.useFahrenheit,
  });

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;
  final bool useFahrenheit;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;

    // Normalize image url from the row
    final rawImageUrl = (row['image_url'] as String?)?.trim();
    final imageUrl =
        (rawImageUrl == null || rawImageUrl.isEmpty || rawImageUrl == 'NULL')
            ? null
            : rawImageUrl;

    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
      imageUrl: imageUrl,
      waterType: waterType,
      tracking: trackingMapFromRow(row),
      idealRanges: idealRangeMapFromRow(row),
    );

    return GestureDetector(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _tankPlaceholder(height: 200, width: double.infinity),
                    )
                  : _tankPlaceholder(height: 200, width: double.infinity),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class TankListTile extends StatelessWidget {
  const TankListTile({
    super.key,
    required this.row,
    required this.onOpen,
    required this.useFahrenheit,
  });

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;
  final bool useFahrenheit;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;

    final rawImageUrl = (row['image_url'] as String?)?.trim();
    final imageUrl =
        (rawImageUrl == null || rawImageUrl.isEmpty || rawImageUrl == 'NULL')
            ? null
            : rawImageUrl;

    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
      imageUrl: imageUrl,
      waterType: waterType,
      tracking: trackingMapFromRow(row),
      idealRanges: idealRangeMapFromRow(row),
    );

    return InkWell(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _tankPlaceholder(height: 56, width: 56),
                  )
                : _tankPlaceholder(height: 56, width: 56),
          ),
          title: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.useGallons,
                builder: (context, useGallons, _) {
                  final volText = useGallons
                      ? '${gallons.toStringAsFixed(0)} gal'
                      : '${liters.toStringAsFixed(0)} L';
                  return Text(
                    '${_labelForWaterType(waterType)} • $volText',
                    style: const TextStyle(color: Colors.white70),
                  );
                },
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white70),
        ),
      ),
    );
  }
}

class TankGridCard extends StatelessWidget {
  const TankGridCard({
    super.key,
    required this.row,
    required this.onOpen,
    required this.useFahrenheit,
  });

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;
  final bool useFahrenheit;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;

    final rawImageUrl = (row['image_url'] as String?)?.trim();
    final imageUrl =
        (rawImageUrl == null || rawImageUrl.isEmpty || rawImageUrl == 'NULL')
            ? null
            : rawImageUrl;

    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
      imageUrl: imageUrl,
      waterType: waterType,
      tracking: trackingMapFromRow(row),
      idealRanges: idealRangeMapFromRow(row),
    );

    return InkWell(
      onTap: () => onOpen(tank),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF182231),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _tankPlaceholder(),
                      )
                    : _tankPlaceholder(),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x14000000),
                        Color(0xCC07111C),
                        Color(0xF5091220),
                      ],
                      stops: [0.0, 0.45, 0.76, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.useGallons,
                  builder: (context, useGallons, _) {
                    final volText = useGallons
                        ? '${gallons.toStringAsFixed(0)} gal'
                        : '${liters.toStringAsFixed(0)} L';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            height: 1.05,
                            shadows: [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_labelForWaterType(waterType)} • $volText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD8E4F2),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Color(0x80000000),
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Latest parameters widget with icons for Temp, pH, TDS
class LatestParams extends StatelessWidget {
  const LatestParams({
    super.key,
    required this.tankId,
    required this.useFahrenheit,
    this.compact = false,
  });

  final String tankId;
  final bool compact;
  final bool useFahrenheit;

  // Match TankDetailPage colors
  static const _kTempBlue = Color(0xFF2F80ED);
  static const _kPhGreen = Color(0xFF27AE60);
  static const _kTdsPurple = Color(0xFF9B51E0);

  Future<Map<String, dynamic>?> _fetchLatest() async {
    try {
      final row = await Supabase.instance.client
          .from('sensor_readings')
          .select('recorded_at, ph, tds, temperature')
          .eq('tank_id', tankId)
          .order('recorded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return row;
    } catch (e, st) {
      debugPrint('LatestParams error for tank $tankId: $e\n$st');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchLatest(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text(
            'Loading latest test...',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          );
        }

        if (snap.hasError) {
          debugPrint('LatestParams FutureBuilder error: ${snap.error}');
          return const Text(
            'Error loading test',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
          );
        }

        final m = snap.data;

        // Defaults: no reading yet means null values and empty date
        double? tempC;
        double? ph;
        double? tds;
        String when = '';

        if (m != null) {
          // DB stores temperature in Fahrenheit (AquaSpec device writes °F)
          final tempF = _asDouble(m['temperature']);
          tempC = tempF == null ? null : (tempF - 32) * 5 / 9;

          ph = _asDouble(m['ph']);
          tds = _asDouble(m['tds']);
          final dt = DateTime.tryParse(m['recorded_at']?.toString() ?? '');
          if (dt != null) {
            when =
                "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}";
          }
        }

        // Convert to display units
        double? tempDisplay;
        String unit = '';
        if (tempC != null) {
          if (useFahrenheit) {
            tempDisplay = (tempC * 9 / 5) + 32;
            unit = '°F';
          } else {
            tempDisplay = tempC;
            unit = '°C';
          }
        }

        if (compact) {
          // Compact view used in list and grid cards. Keep values only.
          final metricsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _compactMetricText(
                text: tempDisplay == null
                    ? 'n/a'
                    : '${tempDisplay.toStringAsFixed(1)}$unit',
                color: _kTempBlue,
              ),
              const SizedBox(width: 14),
              _compactMetricText(
                text: ph == null ? 'n/a' : ph.toStringAsFixed(1),
                color: _kPhGreen,
              ),
              const SizedBox(width: 14),
              _compactMetricText(
                text: tds == null ? 'n/a' : '${tds.toStringAsFixed(0)} ppm',
                color: _kTdsPurple,
              ),
            ],
          );

          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: metricsRow,
          );
        }

        // Full layout with heading (main tank card)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest test',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _iconTile(
                    icon: Icons.thermostat,
                    label: 'Temp',
                    value: tempDisplay == null
                        ? '-'
                        : '${tempDisplay.toStringAsFixed(1)}$unit',
                    color: _kTempBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.science,
                    label: 'pH',
                    value: ph == null ? '-' : ph.toStringAsFixed(1),
                    color: _kPhGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.bubble_chart,
                    label: 'TDS',
                    value: tds == null ? '-' : '${tds.toStringAsFixed(0)} ppm',
                    color: _kTdsPurple,
                  ),
                ),
              ],
            ),
            if (when.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Last test · $when',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _iconTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0b1220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconValue({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

Widget _compactMetricText({
  required String text,
  required Color color,
}) {
  return Text(
    text,
    textAlign: TextAlign.center,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// Shared gray placeholder used in all layouts
Widget _tankPlaceholder({
  double? height,
  double? width,
}) {
  final placeholder = Container(
    height: height,
    width: width,
    decoration: const BoxDecoration(color: Color(0xFF101720)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/brand/Image_placeholder.png',
            fit: BoxFit.cover,
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x14000000),
                Color(0x22000000),
                Color(0x8A02070D),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ],
    ),
  );

  if (height == null && width == null) {
    return placeholder;
  }

  return SizedBox(height: height, width: width, child: placeholder);
}
