import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> exportTankData(BuildContext context) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;

  if (uid == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in to export your data')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No tanks found to export')));
      return;
    }

    final tankById = <String, Map<String, dynamic>>{};
    for (final tank in tanks) {
      final id = tank['id']?.toString();
      if (id != null) tankById[id] = tank;
    }

    final tankIds = tankById.keys.toList();
    if (tankIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No tanks found to export')));
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
      'tank_name,water_type,volume_gallons,reading_time,ph,tds,temperature',
    );

    for (final reading in readings) {
      final tankId = reading['tank_id']?.toString();
      if (tankId == null) continue;

      final tank = tankById[tankId];
      if (tank == null) continue;

      buffer.writeln([
        esc(tank['name']?.toString()),
        esc(tank['water_type']?.toString()),
        esc(tank['volume_gallons']?.toString()),
        esc(reading['recorded_at']?.toString()),
        esc(reading['ph']?.toString()),
        esc(reading['tds']?.toString()),
        esc(reading['temperature']?.toString()),
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
