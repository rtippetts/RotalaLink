import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/rotala_brand.dart';
import 'onboarding/walkthrough.dart';
import 'app_settings.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({
    super.key,
    required this.tankStream,
    required this.onOpenTasks,
    required this.onAddReading,
    required this.greetingName,
  });

  final Stream<List<Map<String, dynamic>>> tankStream;
  final VoidCallback onOpenTasks;
  final VoidCallback onAddReading;
  final String greetingName;

  Future<void> _exportTankData(BuildContext context) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;

    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to export your data')),
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

      final tanksRes = await client
          .from('tanks')
          .select('id,name,water_type,volume_gallons')
          .eq('user_id', uid);

      final tanks = List<Map<String, dynamic>>.from(tanksRes as List);
      if (tanks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tanks found to export')),
        );
        return;
      }

      final tankById = <String, Map<String, dynamic>>{};
      for (final t in tanks) {
        final id = t['id']?.toString();
        if (id != null) tankById[id] = t;
      }

      final tankIds = tankById.keys.toList();
      if (tankIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tanks found to export')),
        );
        return;
      }

      final readingsRes = await client
          .from('sensor_readings')
          .select('tank_id,recorded_at,ph,tds,temperature')
          .inFilter('tank_id', tankIds)
          .order('recorded_at', ascending: true);

      final readings = List<Map<String, dynamic>>.from(readingsRes as List);

      if (readings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No sensor readings found to export')),
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
          'tank_name,water_type,volume_gallons,reading_time,ph,tds,temperature');

      for (final r in readings) {
        final tankId = r['tank_id']?.toString();
        if (tankId == null) continue;
        final tank = tankById[tankId];
        if (tank == null) continue;

        buffer.writeln([
          esc(tank['name']?.toString()),
          esc(tank['water_type']?.toString()),
          esc(tank['volume_gallons']?.toString()),
          esc(r['recorded_at']?.toString()),
          esc(r['ph']?.toString()),
          esc(r['tds']?.toString()),
          esc(r['temperature']?.toString()),
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'aquaspec_tanks_${DateTime.now().toIso8601String().split("T").first}.csv';
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

  void _openSettingsSheet(BuildContext context) {
    bool useFahrenheit = AppSettings.useFahrenheit.value;
    bool useGallons = AppSettings.useGallons.value;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  SwitchListTile(
                    value: useFahrenheit,
                    onChanged: (v) {
                      setSheet(() => useFahrenheit = v);
                      AppSettings.setUseFahrenheit(v);
                    },
                    title: const Text('Temperature units',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      useFahrenheit ? 'Using °F' : 'Using °C',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    activeColor: Colors.tealAccent,
                    contentPadding: EdgeInsets.zero,
                  ),


                  SwitchListTile(
                    value: useGallons,
                    onChanged: (v) {
                      setSheet(() => useGallons = v);
                      AppSettings.setUseGallons(v);
                    },
                    title: const Text('Tank volume units',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      useGallons ? 'Using gallons' : 'Using liters',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    activeColor: Colors.tealAccent,
                    contentPadding: EdgeInsets.zero,
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('View app walkthrough',
                        style: TextStyle(color: Colors.white)),
                    subtitle: const Text('See the quick tour again',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    trailing: const Icon(Icons.school, color: Colors.white),
                    onTap: () async {
                      Navigator.of(ctx).maybePop();
                      await WalkthroughScreen.show(context);
                    },
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: RotalaColors.teal,
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Export tank data (CSV)',
                          style: TextStyle(fontSize: 14)),
                      onPressed: () => _exportTankData(ctx),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
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
              const Icon(Icons.handshake_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Welcome back, $name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ACTION ICONS
          Row(
            children: [
              Expanded(
                child: IconPill(
                  icon: Icons.add_chart,
                  onTap: onAddReading,
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: IconPill(
                  icon: Icons.add_task,
                  onTap: onOpenTasks,
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: IconPill(
                  icon: Icons.settings,
                  onTap: () => _openSettingsSheet(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RotalaColors.teal,
              ),
              icon: const Icon(Icons.file_download_outlined, size: 18),
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
