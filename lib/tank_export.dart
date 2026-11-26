import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';
import 'readings_csv.dart';

Future<void> exportTankData(BuildContext context, {String? tankId}) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;

  try {
    final cachedTanks =
        (await OfflineStore.instance.getCachedTanks(uid))
            .where((tank) => tankId == null || tank['id'].toString() == tankId)
            .toList();
    var cachedOnly = false;
    var tanks = <Map<String, dynamic>>[];
    var readings = <Map<String, dynamic>>[];
    try {
      var query = client.from('tanks').select().eq('user_id', uid);
      if (tankId != null) query = query.eq('id', tankId);
      tanks = List<Map<String, dynamic>>.from(
        await query.timeout(const Duration(seconds: 8)),
      );
      final tankById = {for (final tank in tanks) tank['id'].toString(): tank};
      for (final tank in cachedTanks.where(
        (tank) => tank['__pending'] == true,
      )) {
        tankById[tank['id'].toString()] = tank;
      }
      tanks = tankById.values.toList();
      if (tanks.isNotEmpty) {
        final tankIds = tanks.map((tank) => tank['id'].toString()).toList();
        // Fetch every page; a multi-tank export can exceed the server row limit.
        const pageSize = 500;
        for (var start = 0; ; start += pageSize) {
          final page = await client
              .from('sensor_readings')
              .select()
              .inFilter('tank_id', tankIds)
              .order('recorded_at')
              .order('id')
              .range(start, start + pageSize - 1)
              .timeout(const Duration(seconds: 8));
          readings.addAll(List<Map<String, dynamic>>.from(page));
          if (page.length < pageSize) break;
        }
      }
    } catch (_) {
      cachedOnly = true;
      tanks = cachedTanks;
      readings = [];
    }

    // Merge pending readings even when the server is reachable. Never silently
    // omit tests that the user saved while offline.
    final byId = {for (final row in readings) row['id'].toString(): row};
    for (final tank in tanks) {
      for (final row in await OfflineStore.instance.getCachedReadings(
        '${tank['id']}',
      )) {
        if (cachedOnly || row['__pending'] == true) {
          byId[row['id'].toString()] = {...row, 'tank_id': tank['id']};
        }
      }
    }
    readings =
        byId.values.toList()..sort(
          (a, b) => '${a['recorded_at']}'.compareTo('${b['recorded_at']}'),
        );
    if (!context.mounted) return;
    if (readings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cachedOnly
                ? 'No cached readings available. Connect to the internet and try again.'
                : 'No readings to export yet.',
          ),
        ),
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final date = DateTime.now().toIso8601String().split('T').first;
    final file = File(
      '${directory.path}/rotala_readings_${date}${cachedOnly ? '_cached' : ''}.csv',
    );
    await file.writeAsString(
      buildReadingsCsv(tanks: tanks, readings: readings),
    );
    if (!context.mounted) return;
    final renderObject = context.findRenderObject();
    final origin =
        renderObject is RenderBox && renderObject.hasSize
            ? renderObject.localToGlobal(Offset.zero) & renderObject.size
            : Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(
      [XFile(file.path)],
      text:
          cachedOnly
              ? 'Rotala: cached readings from this device only; this may not include all cloud data.'
              : 'Aquarium readings from Rotala',
      sharePositionOrigin: origin,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not export readings. Please try again.'),
      ),
    );
  }
}
