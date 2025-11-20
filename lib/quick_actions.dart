import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../device_page.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({
    super.key,
    required this.tankStream,
    required this.onOpenAlerts,
    required this.onAddReading,
    required this.greetingName,
  });

  final Stream<List<Map<String, dynamic>>> tankStream;
  final VoidCallback onOpenAlerts;
  final VoidCallback onAddReading;
  final String greetingName;

  Future<_DeviceStatus> _fetchDeviceStatus() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return const _DeviceStatus.unknown();

      final rows = await Supabase.instance.client
          .from('devices')
          .select('connected,last_seen')
          .eq('user_id', uid)
          .order('last_seen', ascending: false)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        final connected = (r['connected'] == true);
        final lastSeenStr = r['last_seen']?.toString();
        final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
        final online = connected ||
            (lastSeen != null &&
                DateTime.now().difference(lastSeen).inMinutes <= 5);

        return _DeviceStatus(online: online, lastSeen: lastSeen);
      }

      return const _DeviceStatus.unknown();
    } catch (_) {
      return const _DeviceStatus.unknown();
    }
  }

  int _countDueToday(List<Map<String, dynamic>> tanks) {
    int due = 0;
    for (final t in tanks) {
      final wt = (t['water_type'] ?? 'freshwater').toString();

      final cadence = wt == 'saltwater'
          ? const Duration(days: 3)
          : wt == 'brackish'
              ? const Duration(days: 5)
              : const Duration(days: 7);

      final lastStr = t['last_measurement_at']?.toString();
      DateTime last = DateTime.now().subtract(const Duration(days: 30));

      if (lastStr != null) {
        final parsed = DateTime.tryParse(lastStr);
        if (parsed != null) last = parsed;
      }

      final next = last.add(cadence);
      final now = DateTime.now();

      final sameDay =
          next.year == now.year && next.month == now.month && next.day == now.day;

      final overdue = next.isBefore(now) && !sameDay;

      if (sameDay || overdue) due += 1;
    }
    return due;
  }

  Future<void> _exportTankData(BuildContext context) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;

  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sign in to export your data'),
      ),
    );
    return;
  }

  try {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Building export file...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Fetch tanks for this user
    final tanksRes = await client
        .from('tanks')
        .select('id,name,water_type,volume_gallons')
        .eq('user_id', uid);

    final tanks = List<Map<String, dynamic>>.from(tanksRes as List);
    if (tanks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tanks found to export'),
        ),
      );
      return;
    }

    // Map tank_id -> tank row for quick lookup
    final tankById = <String, Map<String, dynamic>>{};
    for (final t in tanks) {
      final id = t['id']?.toString();
      if (id != null) {
        tankById[id] = t;
      }
    }

    final tankIds = tankById.keys.toList();
    if (tankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tanks found to export'),
        ),
      );
      return;
    }

    // Fetch readings for the user’s tanks
    final readingsRes = await client
        .from('sensor_readings')
        .select('tank_id,recorded_at,ph,tds,temperature')
        .inFilter('tank_id', tankIds)        // <- changed from .in_(...)
        .order('recorded_at', ascending: true);

    final readings = List<Map<String, dynamic>>.from(readingsRes as List);

    if (readings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sensor readings found to export'),
        ),
      );
      return;
    }

    String esc(String? value) {
      final v = value ?? '';
      if (v.contains(',') || v.contains('"') || v.contains('\n')) {
        final escaped = v.replaceAll('"', '""');
        return '"$escaped"';
      }
      return v;
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'tank_name,water_type,volume_gallons,reading_time,ph,tds,temperature',
    );

    for (final r in readings) {
      final tankId = r['tank_id']?.toString();
      if (tankId == null) continue;
      final tank = tankById[tankId];
      if (tank == null) continue;

      final tankName = tank['name']?.toString();
      final waterType = tank['water_type']?.toString();
      final volume = tank['volume_gallons']?.toString();
      final time = r['recorded_at']?.toString();
      final ph = r['ph']?.toString();
      final tds = r['tds']?.toString();
      final temp = r['temperature']?.toString();

      buffer.writeln([
        esc(tankName),
        esc(waterType),
        esc(volume),
        esc(time),
        esc(ph),
        esc(tds),
        esc(temp),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final fileName =
        'aquaspec_tanks_${DateTime.now().toIso8601String().split('T').first}.csv';
    final file = File('${dir.path}/$fileName');

    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Tank data export from AquaSpec',
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final name = greetingName.isEmpty ? 'there' : greetingName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF122033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Row(
            children: [
              const Icon(
                Icons.handshake_outlined,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Welcome back, $name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Tank summary
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: tankStream,
            builder: (context, snap) {
              final tanks = snap.data ?? const [];
              final due = _countDueToday(tanks);

              return Row(
                children: [
                  const Icon(
                    Icons.waves_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      due == 0
                          ? 'All tanks look good today'
                          : '$due tank${due == 1 ? '' : 's'} need attention today',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 12),

          // ACTION ICONS ROW
          Row(
            children: [
              // Alerts
              Expanded(
                child: IconPill(
                  icon: Icons.notifications,
                  onTap: onOpenAlerts,
                ),
              ),
              const SizedBox(width: 8),

              // Device status -> opens DevicePage
              Expanded(
                child: FutureBuilder<_DeviceStatus>(
                  future: _fetchDeviceStatus(),
                  builder: (context, snap) {
                    final st = snap.data ?? const _DeviceStatus.unknown();
                    final icon = st.online
                        ? Icons.check_circle
                        : Icons.portable_wifi_off;
                    final color =
                        st.online ? Colors.greenAccent : Colors.orangeAccent;

                    return IconPill(
                      icon: icon,
                      iconColor: color,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DevicePage(),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Add reading
              Expanded(
                child: IconPill(
                  icon: Icons.add_chart,
                  onTap: onAddReading,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Export CSV button (solid brand color)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF06b6d4),
              ),
              icon: const Icon(
                Icons.file_download_outlined,
                size: 18,
              ),
              label: const Text(
                'Export tank data (CSV)',
                style: TextStyle(fontSize: 14),
              ),
              onPressed: () => _exportTankData(context),
            ),
          ),
        ],
      ),
    );
  }
}

class IconPill extends StatelessWidget {
  const IconPill({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF0b1220),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Icon(
            icon,
            size: 22,
            color: iconColor ?? Colors.white,
          ),
        ),
      ),
    );
  }
}

class _DeviceStatus {
  final bool online;
  final DateTime? lastSeen;

  const _DeviceStatus({required this.online, this.lastSeen});
  const _DeviceStatus.unknown()
      : online = false,
        lastSeen = null;
}
