import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../tank_detail_page.dart';

class TankCard extends StatelessWidget {
  const TankCard({super.key, required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderImage(),
                    )
                  : _placeholderImage(),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            // latest parameters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LatestParams(tankId: id),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  Widget _placeholderImage() => Container(
        height: 200,
        width: double.infinity,
        color: const Color(0xFF0b1220),
        child: const Center(
          child: Icon(Icons.water, color: Colors.white54, size: 28),
        ),
      );
}

class TankListTile extends StatelessWidget {
  const TankListTile({super.key, required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
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
            child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ph(),
                  )
                : _ph(),
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
              Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              LatestParams(tankId: id, compact: true),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white70),
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  static Widget _ph() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFF0b1220),
        child: const Icon(Icons.water, color: Colors.white54),
      );
}

class TankGridCard extends StatelessWidget {
  const TankGridCard({super.key, required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
    );

    return InkWell(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // taller image to keep aspect pleasant in grid
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _ph(),
                    )
                  : _ph(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: LatestParams(tankId: id, compact: true),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  static Widget _ph() => Container(
        height: 120,
        width: double.infinity,
        color: const Color(0xFF0b1220),
        child: const Center(
          child: Icon(Icons.water, color: Colors.white54, size: 28),
        ),
      );
}

// Latest parameters widget with icons for Temp, pH, TDS
class LatestParams extends StatelessWidget {
  const LatestParams({super.key, required this.tankId, this.compact = false});

  final String tankId;
  final bool compact;

  Future<Map<String, dynamic>?> _fetchLatest() async {
    final row = await Supabase.instance.client
        .from('measurements')
        .select('created_at, ph, tds, temperature, temperature_c')
        .eq('tank_id', tankId)
        .order('created_at', ascending: false)
        .maybeSingle();

    return row;
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
        final m = snap.data;
        if (m == null) {
          return const Text(
            'No tests yet',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          );
        }

        // Read values
        final double? temp = _asDouble(m['temperature']) ??
            _asDouble(m['temperature_c']);
        final double? ph = _asDouble(m['ph']);
        final double? tds = _asDouble(m['tds']);
        final dt = DateTime.tryParse(m['created_at']?.toString() ?? '');
        final when = dt == null
            ? ''
            : "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}";

        // If compact, render a tight row
        if (compact) {
          return Row(
            children: [
              _miniIconValue(
                icon: Icons.thermostat,
                text: temp == null ? '-' : '${temp.toStringAsFixed(1)}°C',
              ),
              const SizedBox(width: 10),
              _miniIconValue(
                icon: Icons.science,
                text: ph == null ? '-' : ph.toStringAsFixed(2),
              ),
              const SizedBox(width: 10),
              _miniIconValue(
                icon: Icons.bubble_chart,
                text: tds == null ? '-' : '${tds.toStringAsFixed(0)} ppm',
              ),
              if (when.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    when,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ],
          );
        }

        // Full layout with heading
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest test',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _iconTile(
                    icon: Icons.thermostat,
                    label: 'Temp',
                    value: temp == null ? '-' : '${temp.toStringAsFixed(1)}°C',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.science,
                    label: 'pH',
                    value: ph == null ? '-' : ph.toStringAsFixed(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.bubble_chart,
                    label: 'TDS',
                    value: tds == null ? '-' : '${tds.toStringAsFixed(0)} ppm',
                  ),
                ),
              ],
            ),
            if (when.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(when,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ],
        );
      },
    );
  }

  // Helpers
  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _iconTile(
      {required IconData icon,
      required String label,
      required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0b1220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconValue({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
