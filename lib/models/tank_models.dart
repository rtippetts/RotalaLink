import 'package:flutter/material.dart';

enum Period { days7, month1, year1, all }
enum ParamType { temperature, ph, tds }

class Tank {
  Tank({
    required this.id,
    required this.name,
    required this.volumeLiters,
    required this.inhabitants,
    this.imageUrl,
    this.waterType,
    this.idealTempMin,
    this.idealTempMax,
    this.idealPhMin,
    this.idealPhMax,
    this.idealTdsMin,
    this.idealTdsMax,
  });

  final String id;
  String name;
  double volumeLiters;
  String inhabitants;
  String? imageUrl;
  String? waterType;

  double? idealTempMin;
  double? idealTempMax;
  double? idealPhMin;
  double? idealPhMax;
  double? idealTdsMin;
  double? idealTdsMax;
}

class MeasurePoint {
  MeasurePoint({
    required this.id,
    required this.at,
    this.tempC,
    this.ph,
    this.tds,
    this.deviceUid,
  });

  final String id;
  final DateTime at;
  final double? tempC;
  final double? ph;
  final double? tds;
  final String? deviceUid;
}

class ParameterReading {
  final ParamType type;
  final double value;
  final String unit;
  final RangeValues goodRange;
  final DateTime timestamp;

  const ParameterReading({
    required this.type,
    required this.value,
    required this.unit,
    required this.goodRange,
    required this.timestamp,
  });
}

class NotePhoto {
  final String id;
  final String storagePath;
  final String publicUrl;

  NotePhoto({
    required this.id,
    required this.storagePath,
    required this.publicUrl,
  });

  factory NotePhoto.fromRow(Map<String, dynamic> r) => NotePhoto(
        id: r['id'],
        storagePath: r['storage_path'],
        publicUrl: r['public_url'],
      );
}

class NoteItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String userId;
  final List<NotePhoto> photos;

  NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.updatedAt,
    required this.userId,
    required this.photos,
  });

  factory NoteItem.fromRow(Map<String, dynamic> r) => NoteItem(
        id: r['id'],
        title: r['title'] ?? '',
        body: r['body'] ?? '',
        createdAt: DateTime.parse(r['created_at']).toLocal(),
        updatedAt: r['updated_at'] == null
            ? null
            : DateTime.parse(r['updated_at']).toLocal(),
        userId: r['user_id'],
        photos: (r['photos'] as List? ?? [])
            .map((p) => NotePhoto.fromRow(p))
            .toList(),
      );
}

class TaskItem {
  final String id;
  final String title;
  final bool done;
  final DateTime? due;
  final String? readingId;

  TaskItem({
    required this.id,
    required this.title,
    required this.done,
    this.due,
    this.readingId,
  });

  factory TaskItem.fromRow(Map<String, dynamic> r) => TaskItem(
        id: r['id'],
        title: r['title'],
        done: r['done'] == true,
        due: r['due_at'] == null
            ? null
            : DateTime.parse(r['due_at']).toLocal(),
        readingId: r['reading_id'],
      );
}
