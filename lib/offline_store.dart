import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OfflineSaveResult { synced, queued }

class OfflineStore {
  OfflineStore._();

  static final OfflineStore instance = OfflineStore._();

  static const _queueKey = 'offline_sync_queue_v1';

  String _tanksKey(String userId) => 'offline_tanks_$userId';
  String _readingsKey(String tankId) => 'offline_readings_$tankId';

  Future<List<Map<String, dynamic>>> getCachedTanks(String userId) async {
    return _readList(_tanksKey(userId));
  }

  Future<void> cacheTanks(String userId, List<Map<String, dynamic>> rows) async {
    final existing = await getCachedTanks(userId);
    final pendingById = <String, Map<String, dynamic>>{
      for (final row in existing)
        if (row['__pending'] == true) row['id'].toString(): Map<String, dynamic>.from(row),
    };

    final merged = <String, Map<String, dynamic>>{
      for (final row in rows) row['id'].toString(): _jsonSafeMap(row),
    };
    merged.addAll(pendingById);

    await _writeList(
      _tanksKey(userId),
      _sortByCreatedAtDescending(merged.values.toList()),
    );
  }

  Future<void> upsertCachedTank(
    String userId,
    Map<String, dynamic> row, {
    required bool pending,
  }) async {
    final existing = await getCachedTanks(userId);
    final merged = <String, Map<String, dynamic>>{
      for (final item in existing) item['id'].toString(): Map<String, dynamic>.from(item),
    };

    final next = _jsonSafeMap(row)
      ..['__pending'] = pending
      ..putIfAbsent('created_at', () => DateTime.now().toUtc().toIso8601String());
    merged[next['id'].toString()] = next;

    await _writeList(
      _tanksKey(userId),
      _sortByCreatedAtDescending(merged.values.toList()),
    );
  }

  Future<List<Map<String, dynamic>>> getCachedReadings(String tankId) async {
    return _readList(_readingsKey(tankId));
  }

  Future<List<Map<String, dynamic>>> getCachedReadingsSince(
    String tankId, {
    String? fromUtc,
  }) async {
    final rows = await getCachedReadings(tankId);
    if (fromUtc == null) return rows;

    final from = DateTime.tryParse(fromUtc)?.toUtc();
    if (from == null) return rows;

    return rows.where((row) {
      final recordedAt = DateTime.tryParse((row['recorded_at'] ?? '').toString())?.toUtc();
      return recordedAt != null && !recordedAt.isBefore(from);
    }).toList();
  }

  Future<void> cacheReadings(String tankId, List<Map<String, dynamic>> rows) async {
    final existing = await getCachedReadings(tankId);
    final pendingById = <String, Map<String, dynamic>>{
      for (final row in existing)
        if (row['__pending'] == true) row['id'].toString(): Map<String, dynamic>.from(row),
    };

    final merged = <String, Map<String, dynamic>>{
      for (final row in rows) row['id'].toString(): _jsonSafeMap(row),
    };
    merged.addAll(pendingById);

    await _writeList(
      _readingsKey(tankId),
      _sortByRecordedAtAscending(merged.values.toList()),
    );
  }

  Future<void> upsertCachedReading(
    String tankId,
    Map<String, dynamic> row, {
    required bool pending,
  }) async {
    final existing = await getCachedReadings(tankId);
    final merged = <String, Map<String, dynamic>>{
      for (final item in existing) item['id'].toString(): Map<String, dynamic>.from(item),
    };

    final next = _jsonSafeMap(row)
      ..['__pending'] = pending
      ..putIfAbsent('recorded_at', () => DateTime.now().toUtc().toIso8601String());
    merged[next['id'].toString()] = next;

    await _writeList(
      _readingsKey(tankId),
      _sortByRecordedAtAscending(merged.values.toList()),
    );
  }

  Future<OfflineSaveResult> saveTank({
    required SupabaseClient client,
    required String userId,
    required Map<String, dynamic> payload,
    String? pendingImageBase64,
    String imageExtension = 'jpg',
  }) async {
    final sanitized = _jsonSafeMap(payload);
    try {
      await syncPending(client);
      if ((sanitized['image_url'] == null || '${sanitized['image_url']}'.isEmpty) &&
          pendingImageBase64 != null) {
        sanitized['image_url'] = await _uploadPendingTankImage(
          client: client,
          userId: userId,
          tankId: sanitized['id'].toString(),
          imageBase64: pendingImageBase64,
          imageExtension: imageExtension,
        );
      }
      await client.from('tanks').upsert(sanitized);
      await upsertCachedTank(userId, sanitized, pending: false);
      return OfflineSaveResult.synced;
    } catch (_) {
      await upsertCachedTank(userId, sanitized, pending: true);
      await _enqueue({
        'type': 'create_tank',
        'user_id': userId,
        'entity_id': sanitized['id'],
        'payload': sanitized,
        if (pendingImageBase64 != null) 'pending_image_base64': pendingImageBase64,
        'image_extension': imageExtension,
      });
      return OfflineSaveResult.queued;
    }
  }

  Future<OfflineSaveResult> saveReading({
    required SupabaseClient client,
    required String tankId,
    required Map<String, dynamic> payload,
  }) async {
    final sanitized = _jsonSafeMap(payload);
    try {
      await syncPending(client);
      await client.from('sensor_readings').upsert(sanitized);
      await upsertCachedReading(tankId, sanitized, pending: false);
      return OfflineSaveResult.synced;
    } catch (_) {
      await upsertCachedReading(tankId, sanitized, pending: true);
      await _enqueue({
        'type': 'create_reading',
        'tank_id': tankId,
        'entity_id': sanitized['id'],
        'payload': sanitized,
      });
      return OfflineSaveResult.queued;
    }
  }

  Future<bool> syncPending(SupabaseClient client) async {
    final queue = await _readQueue();
    if (queue.isEmpty) return false;

    bool changed = false;
    final remaining = <Map<String, dynamic>>[];

    for (final op in queue) {
      try {
        final type = op['type']?.toString();
        switch (type) {
          case 'create_tank':
            final userId = op['user_id'].toString();
            final payload = _jsonSafeMap(op['payload'] as Map<String, dynamic>);
            if ((payload['image_url'] == null || '${payload['image_url']}'.isEmpty) &&
                op['pending_image_base64'] is String) {
              payload['image_url'] = await _uploadPendingTankImage(
                client: client,
                userId: userId,
                tankId: payload['id'].toString(),
                imageBase64: op['pending_image_base64'] as String,
                imageExtension: (op['image_extension'] ?? 'jpg').toString(),
              );
            }
            await client.from('tanks').upsert(payload);
            await upsertCachedTank(userId, payload, pending: false);
            changed = true;
            break;
          case 'create_reading':
            final tankId = op['tank_id'].toString();
            final payload = _jsonSafeMap(op['payload'] as Map<String, dynamic>);
            await client.from('sensor_readings').upsert(payload);
            await upsertCachedReading(tankId, payload, pending: false);
            changed = true;
            break;
          default:
            remaining.add(op);
        }
      } catch (_) {
        remaining.add(op);
      }
    }

    await _writeQueue(remaining);
    return changed;
  }

  Future<int> cachedReadingCount(String tankId) async {
    final rows = await getCachedReadings(tankId);
    return rows.length;
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(rows.map(_jsonSafeMap).toList()));
  }

  Future<List<Map<String, dynamic>>> _readQueue() => _readList(_queueKey);

  Future<void> _writeQueue(List<Map<String, dynamic>> rows) => _writeList(_queueKey, rows);

  Future<void> _enqueue(Map<String, dynamic> op) async {
    final queue = await _readQueue();
    final entityId = op['entity_id']?.toString();
    final type = op['type']?.toString();

    final next = queue
        .where(
          (item) =>
              item['entity_id']?.toString() != entityId ||
              item['type']?.toString() != type,
        )
        .toList();
    next.add(_jsonSafeMap(op));
    await _writeQueue(next);
  }

  Future<String> _uploadPendingTankImage({
    required SupabaseClient client,
    required String userId,
    required String tankId,
    required String imageBase64,
    required String imageExtension,
  }) async {
    final bytes = base64Decode(imageBase64);
    final ext = imageExtension.isEmpty ? 'jpg' : imageExtension.toLowerCase();
    final path = '$userId/tanks/$tankId.$ext';
    await client.storage.from('tank-images').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: FileOptions(
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        upsert: true,
      ),
    );
    return client.storage.from('tank-images').createSignedUrl(path, 60 * 60 * 24 * 30);
  }

  Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> input) {
    return input.map((key, value) => MapEntry(key, _jsonSafeValue(value)));
  }

  dynamic _jsonSafeValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is List) return value.map(_jsonSafeValue).toList();
    if (value is Map) {
      return value.map(
        (key, innerValue) => MapEntry(key.toString(), _jsonSafeValue(innerValue)),
      );
    }
    return value.toString();
  }

  List<Map<String, dynamic>> _sortByCreatedAtDescending(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final aTime = DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime(1970);
      final bTime = DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime(1970);
      return aTime.compareTo(bTime);
    });
    return rows;
  }

  List<Map<String, dynamic>> _sortByRecordedAtAscending(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final aTime = DateTime.tryParse((a['recorded_at'] ?? '').toString()) ?? DateTime(1970);
      final bTime = DateTime.tryParse((b['recorded_at'] ?? '').toString()) ?? DateTime(1970);
      return aTime.compareTo(bTime);
    });
    return rows;
  }
}
