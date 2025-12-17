/// ===============================================================
/// Tank Detail Page — respects AppSettings for units
/// FULLY FIXED: no duplicate helpers, working Edit Tank, working Delete Tank,
/// fixed Supabase Storage upload (no broken uploadBinary call)
/// ===============================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' as share;

import 'theme/rotala_brand.dart';
import 'app_settings.dart';

class TankDetailPage extends StatefulWidget {
  const TankDetailPage({super.key, required this.tank});
  final Tank tank;

  @override
  State<TankDetailPage> createState() => _TankDetailPageState();
}

class _TankDetailPageState extends State<TankDetailPage>
    with SingleTickerProviderStateMixin {
  // Color scheme
  static const _kTempBlue = Color(0xFF2F80ED);
  static const _kPhGreen = Color(0xFF27AE60);
  static const _kTdsPurple = Color(0xFF9B51E0);
  static const _kCardBg = Color(0xFF1f2937);
  static const _kPageBg = Color(0xFF111827);
  static const _kDanger = Color(0xFFE74C3C);

  // Defaults (canonical storage)
  // Your historical defaults were 0–100°C, but you now store °F in DB.
  static const double _defaultIdealTempMinF = 32.0; // 0°C
  static const double _defaultIdealTempMaxF = 212.0; // 100°C
  static const double _defaultIdealPhMin = 0.0;
  static const double _defaultIdealPhMax = 14.0;
  static const double _defaultIdealTdsMin = 0.0;
  static const double _defaultIdealTdsMax = 5000.0;

Widget _logoAvatarFallback({required double size}) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0xFF1a1a1a), // same as _tankPlaceholder
      shape: BoxShape.circle,
    ),
    child: Center(
      child: Opacity(
        opacity: 0.5,
        child: SizedBox(
          height: size * 0.55, // ~40%–60% looks best in a circle
          child: Image.asset(
            'assets/brand/rotalafinalsquare2.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}

  Color _seriesColor(ParamType t) => switch (t) {
        ParamType.temperature => _kTempBlue,
        ParamType.ph => _kPhGreen,
        ParamType.tds => _kTdsPurple,
      };

  late final TabController _tabController =
      TabController(length: 4, vsync: this);

  bool _loading = true;
  List<MeasurePoint> _points = [];

  ParamType _series = ParamType.temperature;
  Period _period = Period.month1;

  // Persisted entities
  List<NoteItem> _notes = [];
  List<TaskItem> _tasks = [];

  // Track dismissed warnings for this session (reading timestamp + param)
  final Set<String> _dismissedWarningKeys = {};

  // Unit preferences (driven by AppSettings)
  bool _useFahrenheit = true;
  bool _useGallons = true;

  @override
  void initState() {
    super.initState();

    // React to tab changes so FAB updates per tab
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Initialize from current settings
    _useFahrenheit = AppSettings.useFahrenheit.value;
    _useGallons = AppSettings.useGallons.value;

    // Listen for future changes so this page reacts live
    AppSettings.useFahrenheit.addListener(_onSettingsChanged);
    AppSettings.useGallons.addListener(_onSettingsChanged);

    // In case load has not been called yet elsewhere
    AppSettings.load();

    _refreshAll();
  }

  @override
  void dispose() {
    AppSettings.useFahrenheit.removeListener(_onSettingsChanged);
    AppSettings.useGallons.removeListener(_onSettingsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {
      _useFahrenheit = AppSettings.useFahrenheit.value;
      _useGallons = AppSettings.useGallons.value;
    });
  }

  double _cToF(double c) => c * 9.0 / 5.0 + 32.0;
  double _fToC(double f) => (f - 32.0) * 5.0 / 9.0;

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadMeasurements(),
      _loadNotes(),
      _loadTasks(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  // ---------------- Measurements ----------------
  Future<void> _loadMeasurements() async {
    final supa = Supabase.instance.client;
    final fromUtc = _periodFromDate(_period)?.toUtc().toIso8601String();

    var q = supa
        .from('sensor_readings')
        .select('id, tank_id, recorded_at, temperature, ph, tds, device_uid')
        .eq('tank_id', widget.tank.id);

    if (fromUtc != null) q = q.gte('recorded_at', fromUtc);

    final rows = await q.order('recorded_at', ascending: true);
    _points = (rows as List)
        .map((r) => MeasurePoint(
              id: r['id'] as String,
              at: DateTime.parse(r['recorded_at']).toLocal(),
              tempC: (() {
                final tempF =
                    (r['temperature'] as num?)?.toDouble(); // DB stores °F
                return tempF == null ? null : _fToC(tempF); // internal is °C
              })(),
              ph: (r['ph'] as num?)?.toDouble(),
              tds: (r['tds'] as num?)?.toDouble(),
              deviceUid: r['device_uid'] as String?,
            ))
        .toList();
  }

  DateTime? _periodFromDate(Period p) {
    final now = DateTime.now();
    return switch (p) {
      Period.days7 => now.subtract(const Duration(days: 7)),
      Period.month1 => DateTime(now.year, now.month - 1, now.day),
      Period.year1 => DateTime(now.year - 1, now.month, now.day),
      Period.all => null,
    };
  }

  // Latest tiles (per-parameter recency)
  ParameterReading? get latestTemp {
    final v = _points.where((p) => p.tempC != null);
    if (v.isEmpty) return null;
    final last = v.last;

    final valueC = last.tempC!;
    final valueDisplay = _useFahrenheit ? _cToF(valueC) : valueC;

    final minF = widget.tank.idealTempMin ?? _defaultIdealTempMinF;
    final maxF = widget.tank.idealTempMax ?? _defaultIdealTempMaxF;

    final rangeDisplay = _useFahrenheit
        ? RangeValues(minF, maxF)
        : RangeValues(_fToC(minF), _fToC(maxF));

    return ParameterReading(
      type: ParamType.temperature,
      value: valueDisplay,
      unit: _useFahrenheit ? '°F' : '°C',
      goodRange: rangeDisplay,
      timestamp: last.at,
    );
  }

  ParameterReading? get latestPh {
    final v = _points.where((p) => p.ph != null);
    if (v.isEmpty) return null;
    final last = v.last;
    return ParameterReading(
      type: ParamType.ph,
      value: last.ph!,
      unit: 'pH',
      goodRange: RangeValues(
        widget.tank.idealPhMin ?? _defaultIdealPhMin,
        widget.tank.idealPhMax ?? _defaultIdealPhMax,
      ),
      timestamp: last.at,
    );
  }

  ParameterReading? get latestTds {
    final v = _points.where((p) => p.tds != null);
    if (v.isEmpty) return null;
    final last = v.last;
    return ParameterReading(
      type: ParamType.tds,
      value: last.tds!,
      unit: 'ppm',
      goodRange: RangeValues(
        widget.tank.idealTdsMin ?? _defaultIdealTdsMin,
        widget.tank.idealTdsMax ?? _defaultIdealTdsMax,
      ),
      timestamp: last.at,
    );
  }

  // ---------------- Notes ----------------
  Future<void> _loadNotes() async {
    final rows = await Supabase.instance.client
        .from('tank_notes')
        .select(
            'id, title, body, created_at, updated_at, user_id, photos:tank_note_photos(id, storage_path, public_url, created_at)')
        .eq('tank_id', widget.tank.id)
        .order('created_at', ascending: false);
    _notes = (rows as List)
        .map((r) => NoteItem.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> _createOrEditNote({NoteItem? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final body = TextEditingController(text: existing?.body ?? '');
    final formKey = GlobalKey<FormState>();
    final picker = ImagePicker();
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final bucket = 'tank-notes';
    List<NotePhoto> photos = [...(existing?.photos ?? [])];
    bool busy = false;

    Future<void> addPhotos() async {
      final xfiles = await picker.pickMultiImage(imageQuality: 90);
      if (xfiles.isEmpty) return;
      busy = true;
      if (mounted) setState(() {});
      final noteId = existing?.id ?? const Uuid().v4();
      for (final xf in xfiles) {
        final ext = xf.path.split('.').last.toLowerCase();
        final pid = const Uuid().v4();
        final path = '$uid/tanks/${widget.tank.id}/notes/$noteId/$pid.$ext';
        await Supabase.instance.client.storage
            .from(bucket)
            .upload(path, File(xf.path));
        final url =
            Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
        photos.add(NotePhoto(id: pid, storagePath: path, publicUrl: url));
      }
      busy = false;
      if (mounted) setState(() {});
    }

    Future<void> deleteStagedPhoto(NotePhoto p) async {
      await Supabase.instance.client.storage.from(bucket).remove([p.storagePath]);
      photos.removeWhere((x) => x.storagePath == p.storagePath);
      if (mounted) setState(() {});
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: const [
                      Icon(Icons.event_note, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Note',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: body,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in photos.take(6))
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  p.publicUrl,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: InkWell(
                                  onTap: () async {
                                    await deleteStagedPhoto(p);
                                    setSheet(() {});
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  await addPhotos();
                                  setSheet(() {});
                                },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add photos'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;

                                  final supa = Supabase.instance.client;
                                  final userId = uid;

                                  if (existing == null) {
                                    final noteId = const Uuid().v4();
                                    await supa.from('tank_notes').insert({
                                      'id': noteId,
                                      'tank_id': widget.tank.id,
                                      'user_id': userId,
                                      'title': title.text.trim(),
                                      'body': body.text.trim(),
                                    });

                                    if (photos.isNotEmpty) {
                                      await supa.from('tank_note_photos').insert([
                                        for (final p in photos)
                                          {
                                            'note_id': noteId,
                                            'storage_path': p.storagePath,
                                            'public_url': p.publicUrl,
                                          }
                                      ]);
                                    }
                                  } else {
                                    await supa.from('tank_notes').update({
                                      'title': title.text.trim(),
                                      'body': body.text.trim(),
                                    }).eq('id', existing.id);

                                    final existingPaths =
                                        existing.photos.map((e) => e.storagePath).toSet();
                                    final newOnes = photos
                                        .where((p) => !existingPaths.contains(p.storagePath))
                                        .toList();
                                    if (newOnes.isNotEmpty) {
                                      await supa.from('tank_note_photos').insert([
                                        for (final p in newOnes)
                                          {
                                            'note_id': existing.id,
                                            'storage_path': p.storagePath,
                                            'public_url': p.publicUrl,
                                          }
                                      ]);
                                    }
                                  }

                                  if (!mounted) return;
                                  Navigator.pop(ctx, true);
                                },
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      await _loadNotes();
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteNote(NoteItem n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This will remove the note and its photos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final supa = Supabase.instance.client;
    if (n.photos.isNotEmpty) {
      await supa.storage
          .from('tank-notes')
          .remove([for (final p in n.photos) p.storagePath]);
      await supa.from('tank_note_photos').delete().eq('note_id', n.id);
    }
    await supa.from('tank_notes').delete().eq('id', n.id);
    await _loadNotes();
    if (mounted) setState(() {});
  }

  // ---------------- Tasks ----------------
  Future<void> _loadTasks() async {
    final rows = await Supabase.instance.client
        .from('tank_tasks')
        .select('id, title, done, due_at, reading_id, created_at, updated_at')
        .eq('tank_id', widget.tank.id)
        .order('created_at', ascending: false);
    _tasks = (rows as List)
        .map((r) => TaskItem.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> _createOrEditTask({
    TaskItem? existing,
    String? readingId,
    String? suggestedTitle,
  }) async {
    final title =
        TextEditingController(text: existing?.title ?? suggestedTitle ?? '');
    DateTime? due = existing?.due;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Task' : 'Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(due == null
                    ? 'No due date'
                    : 'Due: ${_timeExact(due!)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: due ?? now,
                      firstDate: now.subtract(const Duration(days: 3650)),
                      lastDate: now.add(const Duration(days: 3650)),
                    );
                    if (d == null) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(due ?? now),
                    );
                    setSheet(() => due = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          (t?.hour ?? 0),
                          (t?.minute ?? 0),
                        ));
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
    if (saved != true) return;

    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser!.id;

    if (existing == null) {
      await supa.from('tank_tasks').insert({
        'tank_id': widget.tank.id,
        'user_id': userId,
        'title': title.text.trim(),
        'due_at': due?.toUtc().toIso8601String(),
        'reading_id': readingId,
      });
    } else {
      await supa.from('tank_tasks').update({
        'title': title.text.trim(),
        'due_at': due?.toUtc().toIso8601String(),
      }).eq('id', existing.id);
    }

    await _loadTasks();
    if (mounted) setState(() {});
  }

  Future<void> _deleteTask(TaskItem t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await Supabase.instance.client.from('tank_tasks').delete().eq('id', t.id);
    await _loadTasks();
    if (mounted) setState(() {});
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final volumeLabel = _useGallons
        ? '${widget.tank.volumeGallons.toStringAsFixed(0)} gal'
        : '${widget.tank.volumeLiters.toStringAsFixed(0)} L';

    final subtitle =
        '$volumeLabel • ${_labelForWaterType(widget.tank.waterType ?? 'freshwater')}';

    final hasAppBarImg =
        (widget.tank.imageUrl != null && widget.tank.imageUrl!.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: _kPageBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
  radius: 20,
  backgroundColor: Colors.grey.shade700,
  backgroundImage: hasAppBarImg ? NetworkImage(widget.tank.imageUrl!) : null,
  child: hasAppBarImg ? null : _logoAvatarFallback(size: 40),
),

            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.tank.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$subtitle  •  ${_lastMeasuredLabel()}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Edit tank',
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _openEditTank,
          ),
          const SizedBox(width: 6),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: SizedBox(height: 4),
        ),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.tealAccent,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Readings'),
              Tab(text: 'Notes'),
              Tab(text: 'Tasks'),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverview(_kCardBg),
                  _buildReadings(_kCardBg),
                  _buildNotes(_kCardBg),
                  _buildTasks(_kCardBg),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // ---------- Context aware FAB ----------
  Widget _buildFab() {
    final idx = _tabController.index;

    IconData secondaryIcon;
    VoidCallback? onPressed;

    switch (idx) {
      case 0:
        secondaryIcon = Icons.add_chart;
        onPressed = _openManualReadingForm;
        break;
      case 1:
        secondaryIcon = Icons.file_download_outlined;
        onPressed = _exportTankCsv;
        break;
      case 2:
        secondaryIcon = Icons.event_note;
        onPressed = () => _createOrEditNote();
        break;
      case 3:
        secondaryIcon = Icons.add_task;
        onPressed = () => _createOrEditTask();
        break;
      default:
        secondaryIcon = Icons.science;
        onPressed = _openManualReadingForm;
        break;
    }

    return FloatingActionButton.extended(
      backgroundColor: RotalaColors.teal,
      onPressed: onPressed,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (idx != 0) const SizedBox(width: 5),
          Icon(secondaryIcon, size: 30, color: Colors.white),
        ],
      ),
      label: const SizedBox.shrink(),
      extendedPadding: const EdgeInsets.fromLTRB(20, 20, 14, 20),
    );
  }

  Future<void> _exportTankCsv() async {
    try {
      final supa = Supabase.instance.client;

      final rows = await supa
          .from('sensor_readings')
          .select('recorded_at, temperature, ph, tds, device_uid')
          .eq('tank_id', widget.tank.id)
          .order('recorded_at', ascending: true);

      final list = rows as List;

      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No readings to export for this tank')),
        );
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln(
        'recorded_at_local,recorded_at_utc,temperature_c,temperature_f,ph,tds_ppm,device_uid',
      );

      String fmtNum(num? n, {int decimals = 2}) {
        if (n == null) return '';
        return n.toStringAsFixed(decimals);
      }

      for (final r in list) {
        final recordedUtc = DateTime.parse(r['recorded_at'] as String).toUtc();
        final recordedLocal = recordedUtc.toLocal();

        final tempF = (r['temperature'] as num?)?.toDouble(); // DB stores °F
        final tempC = tempF == null ? null : _fToC(tempF);

        final ph = (r['ph'] as num?)?.toDouble();
        final tds = (r['tds'] as num?)?.toDouble();
        final deviceUid = r['device_uid'] as String?;

        buffer.writeln([
          recordedLocal.toIso8601String(),
          recordedUtc.toIso8601String(),
          fmtNum(tempC, decimals: 2),
          fmtNum(tempF, decimals: 2),
          fmtNum(ph, decimals: 3),
          fmtNum(tds, decimals: 0),
          deviceUid ?? '',
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final safeTankName = widget.tank.name
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .toLowerCase();
      final file = File('${dir.path}/tank_${safeTankName}_readings.csv');

      await file.writeAsString(buffer.toString());

      await share.Share.shareXFiles(
        [share.XFile(file.path)],
        text: 'Sensor readings for tank "${widget.tank.name}"',
        subject: 'Tank readings export',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${list.length} readings for ${widget.tank.name}')),
      );
    } catch (e, st) {
      debugPrint('CSV export failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
    }
  }

  // ---------- Overview ----------
  Widget _buildOverview(Color card) {
    final tiles =
        [latestTemp, latestPh, latestTds].whereType<ParameterReading>().toList();

    bool _oor(ParameterReading r) =>
        r.value < r.goodRange.start || r.value > r.goodRange.end;
    String _key(ParameterReading r) =>
        '${r.type.name}@${r.timestamp.toIso8601String()}';

    final tempOOR = latestTemp != null &&
        _oor(latestTemp!) &&
        !_dismissedWarningKeys.contains(_key(latestTemp!));
    final phOOR = latestPh != null &&
        _oor(latestPh!) &&
        !_dismissedWarningKeys.contains(_key(latestPh!));
    final tdsOOR = latestTds != null &&
        _oor(latestTds!) &&
        !_dismissedWarningKeys.contains(_key(latestTds!));

    return SafeArea(
      bottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (tiles.isNotEmpty)
            Row(
              children: List.generate(tiles.length, (i) {
                final reading = tiles[i];
                final selected = reading.type == _series;
                final showBadge = ((reading.type == ParamType.temperature && tempOOR) ||
                    (reading.type == ParamType.ph && phOOR) ||
                    (reading.type == ParamType.tds && tdsOOR));
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 12),
                    child: GestureDetector(
                      onTap: () => setState(() => _series = reading.type),
                      child: _MiniParameterCard(
                        reading: reading,
                        color: _seriesColor(reading.type),
                        selected: selected,
                        showBadge: showBadge,
                      ),
                    ),
                  ),
                );
              }),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
              child: const Text('No recent measurements', style: TextStyle(color: Colors.white70)),
            ),
          const SizedBox(height: 12),

          DropdownButtonFormField<Period>(
            value: _period,
            dropdownColor: const Color(0xFF0b1220),
            decoration: const InputDecoration(
              labelText: 'Time range',
              labelStyle: TextStyle(color: Colors.white70),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: Period.days7, child: Text('Last 7 days')),
              DropdownMenuItem(value: Period.month1, child: Text('Last month')),
              DropdownMenuItem(value: Period.year1, child: Text('Last year')),
              DropdownMenuItem(value: Period.all, child: Text('All time')),
            ],
            onChanged: (v) async {
              setState(() => _period = v ?? _period);
              await _loadMeasurements();
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),

          Builder(builder: (_) {
            ParameterReading? r;
            if (_series == ParamType.temperature) r = latestTemp;
            if (_series == ParamType.ph) r = latestPh;
            if (_series == ParamType.tds) r = latestTds;
            if (r == null) return const SizedBox.shrink();

            final isOOR = (r.value < r.goodRange.start || r.value > r.goodRange.end);
            final k = '${r.type.name}@${r.timestamp.toIso8601String()}';
            if (!isOOR || _dismissedWarningKeys.contains(k)) return const SizedBox.shrink();

            final text =
                '${_labelForParam(r.type)} out of range: ${_formatValue(r)} ${r.unit}. Target ${_formatRange(r.goodRange)}';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kDanger.withOpacity(0.12),
                border: Border.all(color: _kDanger),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.error_outline, color: _kDanger),
                      SizedBox(width: 8),
                      Text('Warning',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(text, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Dismiss warning?'),
                              content: const Text('Are you sure you want to dismiss this warning?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Dismiss'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) setState(() => _dismissedWarningKeys.add(k));
                        },
                        child: const Text('Dismiss'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          final title =
                              'Fix ${_labelForParam(r!.type)} (${_formatValue(r)} ${r.unit}) • Target ${_formatRange(r.goodRange)}';
                          final readingId = _mostRecentReadingIdFor(_series);
                          _createOrEditTask(suggestedTitle: title, readingId: readingId);
                          _tabController.index = 3;
                        },
                        icon: const Icon(Icons.add_task),
                        label: const Text('Set Task'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              height: 260,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : _spotsFor(_series).isEmpty
                      ? const Center(
                          child: Text('No data for selected parameter',
                              style: TextStyle(color: Colors.white54)),
                        )
                      : LineChart(_buildSingleSeriesChartData(_series)),
            ),
          ),
        ],
      ),
    );
  }

  String? _mostRecentReadingIdFor(ParamType t) {
    Iterable<MeasurePoint> v;
    switch (t) {
      case ParamType.temperature:
        v = _points.where((p) => p.tempC != null);
        break;
      case ParamType.ph:
        v = _points.where((p) => p.ph != null);
        break;
      case ParamType.tds:
        v = _points.where((p) => p.tds != null);
        break;
    }
    if (v.isEmpty) return null;
    return v.last.id;
  }

  // ---------- Readings ----------
  Widget _buildReadings(Color card) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: _openManualReadingForm,
          icon: const Icon(Icons.add_chart),
          label: const Text('Add Reading'),
        ),
        const SizedBox(height: 12),
        ..._points.reversed.take(200).map((p) {
          final isManual = p.deviceUid == null;
          final iconData = isManual ? Icons.edit_note : Icons.sensors;
          final iconColor = isManual ? Colors.tealAccent : Colors.white70;

          final tempC = p.tempC;
          final tempUnit = _useFahrenheit ? '°F' : '°C';

          String tempStr;
          if (tempC == null) {
            tempStr = '-';
          } else {
            final displayTemp = _useFahrenheit ? _cToF(tempC) : tempC;
            tempStr = displayTemp.toStringAsFixed(1);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              dense: true,
              textColor: Colors.white,
              iconColor: Colors.white70,
              leading: Icon(iconData, color: iconColor),
              title: Text(_timeExact(p.at)),
              subtitle: Text(
                'Temp: $tempStr $tempUnit   '
                'pH: ${p.ph?.toStringAsFixed(2) ?? '-'}   '
                'TDS: ${p.tds?.toStringAsFixed(0) ?? '-'} ppm',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: isManual ? 'Edit manual reading' : 'Edit device reading',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editManualReading(p),
                  ),
                  IconButton(
                    tooltip: 'Delete reading',
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteReading(p),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _editManualReading(MeasurePoint p) async {
    final tempUnit = _useFahrenheit ? '°F' : '°C';

    final initialTempText = p.tempC == null
        ? ''
        : (_useFahrenheit
            ? _cToF(p.tempC!).toStringAsFixed(1)
            : p.tempC!.toStringAsFixed(1));

    final temp = TextEditingController(text: initialTempText);
    final ph = TextEditingController(text: p.ph?.toString() ?? '');
    final tds = TextEditingController(text: p.tds?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit reading'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numField(
                'Temperature ($tempUnit)',
                temp,
                helper: _useFahrenheit ? '32 to 122' : '0 to 50',
                validator: (v) => _optionalRange(
                  v,
                  _useFahrenheit ? 32 : 0,
                  _useFahrenheit ? 122 : 50,
                  _useFahrenheit
                      ? '32 to 122 $tempUnit or blank'
                      : '0 to 50 $tempUnit or blank',
                ),
              ),
              const SizedBox(height: 8),
              _numField(
                'pH',
                ph,
                decimals: 2,
                helper: '0 to 14',
                validator: (v) => _optionalRange(v, 0, 14, '0 to 14 or blank'),
              ),
              const SizedBox(height: 8),
              _numField(
                'TDS (ppm)',
                tds,
                helper: '0 to 5000',
                validator: (v) =>
                    _optionalRange(v, 0, 5000, '0 to 5000 or blank'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Recorded at: ${_timeExact(p.at)} (locked)',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final anyEntered = temp.text.trim().isNotEmpty ||
                  ph.text.trim().isNotEmpty ||
                  tds.text.trim().isNotEmpty;
              if (!anyEntered) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter at least one value.')));
                return;
              }
              if (!formKey.currentState!.validate()) return;

              double? tempC;
              final tempText = temp.text.trim();
              if (tempText.isNotEmpty) {
                final displayVal = double.parse(tempText);
                tempC = _useFahrenheit ? _fToC(displayVal) : displayVal;
              }

              await Supabase.instance.client.from('sensor_readings').update({
                'temperature': tempC == null ? null : _cToF(tempC), // store °F in DB
                'ph': ph.text.trim().isEmpty ? null : double.parse(ph.text.trim()),
                'tds': tds.text.trim().isEmpty ? null : double.parse(tds.text.trim()),
              }).eq('id', p.id);

              if (!mounted) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _loadMeasurements();
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteReading(MeasurePoint p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete reading?'),
        content: const Text('This will permanently remove this reading.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final supa = Supabase.instance.client;
      await supa.from('sensor_readings').delete().eq('id', p.id);
      await _loadMeasurements();
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Error deleting reading: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /// ---------- Notes UI ----------
  Widget _buildNotes(Color card) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: () => _createOrEditNote(),
          icon: const Icon(Icons.event_note),
          label: const Text('Add Note'),
        ),
        const SizedBox(height: 12),
        ..._notes.map(
          (n) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.event_note, color: Colors.white70),
              title: Text(n.title, style: const TextStyle(color: Colors.white)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  if (n.body.trim().isNotEmpty)
                    Text(n.body, style: const TextStyle(color: Colors.white70)),
                  if (n.photos.isNotEmpty) const SizedBox(height: 8),
                  if (n.photos.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in n.photos.take(3))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              p.publicUrl,
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            ),
                          ),
                        if (n.photos.length > 3)
                          Text('+${n.photos.length - 3} more',
                              style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    _timeExact(n.createdAt),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onSelected: (v) {
                  if (v == 'edit') _createOrEditNote(existing: n);
                  if (v == 'delete') _deleteNote(n);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Tasks UI ----------
  Widget _buildTasks(Color card) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: () => _createOrEditTask(),
            icon: const Icon(Icons.add_task),
            label: const Text('Add Task'),
          );
        }

        final t = _tasks[i - 1];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: CheckboxListTile(
            value: t.done,
            onChanged: (v) async {
              await Supabase.instance.client
                  .from('tank_tasks')
                  .update({'done': v ?? false}).eq('id', t.id);
              await _loadTasks();
              if (mounted) setState(() {});
            },
            title: Text(t.title, style: const TextStyle(color: Colors.white)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.due != null)
                  Text('Due ${_timeExact(t.due!)}',
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            activeColor: Colors.teal,
            secondary: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onSelected: (v) {
                if (v == 'edit') _createOrEditTask(existing: t);
                if (v == 'delete') _deleteTask(t);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Chart helpers ----------
  DateTime get _periodStart {
    final custom = _periodFromDate(_period);
    final start = custom ?? (_points.isNotEmpty ? _points.first.at : DateTime.now());
    return DateTime(start.year, start.month, start.day);
  }

  double _xDay(DateTime d) => d.difference(_periodStart).inMinutes / (60 * 24);

  String _mmddForTick(double x) {
    final dt = _periodStart.add(Duration(days: x.round()));
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d';
  }

  RangeValues _goodRangeFor(ParamType type) => switch (type) {
        ParamType.temperature => () {
            final minF = widget.tank.idealTempMin ?? _defaultIdealTempMinF;
            final maxF = widget.tank.idealTempMax ?? _defaultIdealTempMaxF;
            return _useFahrenheit
                ? RangeValues(minF, maxF)
                : RangeValues(_fToC(minF), _fToC(maxF));
          }(),
        ParamType.ph => RangeValues(
            widget.tank.idealPhMin ?? _defaultIdealPhMin,
            widget.tank.idealPhMax ?? _defaultIdealPhMax,
          ),
        ParamType.tds => RangeValues(
            widget.tank.idealTdsMin ?? _defaultIdealTdsMin,
            widget.tank.idealTdsMax ?? _defaultIdealTdsMax,
          ),
      };

  List<FlSpot> _spotsFor(ParamType type) {
    List<double?> ys;
    switch (type) {
      case ParamType.temperature:
        ys = _points
            .map((e) => e.tempC == null
                ? null
                : (_useFahrenheit ? _cToF(e.tempC!) : e.tempC))
            .toList();
        break;
      case ParamType.ph:
        ys = _points.map((e) => e.ph).toList();
        break;
      case ParamType.tds:
        ys = _points.map((e) => e.tds).toList();
        break;
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < _points.length; i++) {
      final y = ys[i];
      if (y == null) continue;
      final x = _xDay(_points[i].at);
      spots.add(FlSpot(x, y));
    }
    return spots;
  }

  LineChartData _buildSingleSeriesChartData(ParamType type) {
    final spots = _spotsFor(type);
    final color = _seriesColor(type);

    double? minY, maxY;
    if (spots.isNotEmpty) {
      final ys = spots.map((s) => s.y).toList();
      final lo = ys.reduce((a, b) => a < b ? a : b);
      final hi = ys.reduce((a, b) => a > b ? a : b);

      if (type == ParamType.ph) {
        const pad = 0.2;
        minY = (lo - pad).clamp(5.0, 14.0);
        maxY = (hi + pad).clamp(5.0, 14.0);
      } else {
        final pad = (hi - lo).abs() * 0.15 + 0.5;
        minY = lo - pad;
        maxY = hi + pad;
      }
    }

    double minX;
    double maxX;
    if (spots.isEmpty) {
      minX = 0;
      maxX = 1;
    } else {
      final firstX = spots.first.x;
      final lastX = spots.last.x;
      const pad = 0.5;
      minX = firstX - pad;
      maxX = lastX + pad;
      if (minX >= maxX) {
        minX = firstX;
        maxX = firstX + 1;
      }
    }

    final band = _goodRangeFor(type);
    final shade = _kDanger.withOpacity(0.10);

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          dotData: const FlDotData(show: true),
          color: color,
          barWidth: 2,
        ),
      ],
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(y: band.start, color: _kDanger, strokeWidth: 1.5, dashArray: [4, 3]),
          HorizontalLine(y: band.end, color: _kDanger, strokeWidth: 1.5, dashArray: [4, 3]),
        ],
      ),
      rangeAnnotations: RangeAnnotations(
        horizontalRangeAnnotations: [
          HorizontalRangeAnnotation(
            y1: (minY ?? band.start) - 9999,
            y2: band.start,
            color: shade,
          ),
          HorizontalRangeAnnotation(
            y1: band.end,
            y2: (maxY ?? band.end) + 9999,
            color: shade,
          ),
        ],
      ),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (maxX - minX) <= 7 ? 1 : ((maxX - minX) / 6).ceilToDouble(),
            getTitlesWidget: (x, _) => Text(
              _mmddForTick(x),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget: (y, _) => Text(
              type == ParamType.ph ? y.toStringAsFixed(1) : y.toStringAsFixed(0),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
    );
  }

  // ---------- Manual Reading FAB ----------
  Future<void> _openManualReadingForm() async {
    final tempUnit = _useFahrenheit ? '°F' : '°C';

    final temp = TextEditingController();
    final ph = TextEditingController();
    final tds = TextEditingController();
    DateTime localWhen = DateTime.now();
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pickDateTime() async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: localWhen,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d == null) return;
            final t = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(localWhen),
            );
            if (t == null) return;
            setSheet(() => localWhen = DateTime(d.year, d.month, d.day, t.hour, t.minute));
          }

          String whenLabel() {
            final y = localWhen.year.toString().padLeft(4, '0');
            final m = localWhen.month.toString().padLeft(2, '0');
            final d = localWhen.day.toString().padLeft(2, '0');
            final hh = localWhen.hour.toString().padLeft(2, '0');
            final mm = localWhen.minute.toString().padLeft(2, '0');
            return '$y-$m-$d • $hh:$mm (local)';
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.science, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Add manual reading',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      tileColor: Colors.white12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onTap: pickDateTime,
                      leading: const Icon(Icons.schedule, color: Colors.white),
                      title: Text(whenLabel(), style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.edit_calendar, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    _numField(
                      'Temperature ($tempUnit)',
                      temp,
                      helper: _useFahrenheit ? '32 to 122' : '0 to 50',
                      validator: (v) => _optionalRange(
                        v,
                        _useFahrenheit ? 32 : 0,
                        _useFahrenheit ? 122 : 50,
                        _useFahrenheit
                            ? 'Enter 32 to 122 $tempUnit or leave blank'
                            : 'Enter 0 to 50 $tempUnit or leave blank',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _numField(
                      'pH',
                      ph,
                      decimals: 2,
                      helper: '0 to 14',
                      validator: (v) => _optionalRange(v, 0, 14, 'Enter 0 to 14 pH or leave blank'),
                    ),
                    const SizedBox(height: 10),
                    _numField(
                      'TDS (ppm)',
                      tds,
                      helper: '0 to 5000',
                      validator: (v) => _optionalRange(v, 0, 5000, 'Enter 0 to 5000 ppm or leave blank'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            onPressed: saving
                                ? null
                                : () async {
                                    final anyEntered = temp.text.trim().isNotEmpty ||
                                        ph.text.trim().isNotEmpty ||
                                        tds.text.trim().isNotEmpty;
                                    if (!anyEntered) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Enter at least one parameter.')),
                                      );
                                      return;
                                    }
                                    if (!formKey.currentState!.validate()) return;

                                    setSheet(() => saving = true);
                                    try {
                                      final supa = Supabase.instance.client;

                                      double? tempC;
                                      final tempText = temp.text.trim();
                                      if (tempText.isNotEmpty) {
                                        final displayVal = double.parse(tempText);
                                        tempC = _useFahrenheit ? _fToC(displayVal) : displayVal;
                                      }

                                      await supa.from('sensor_readings').insert({
                                        'tank_id': widget.tank.id,
                                        'recorded_at': localWhen.toUtc().toIso8601String(),
                                        'temperature': tempC == null ? null : _cToF(tempC), // store °F in DB
                                        'ph': ph.text.trim().isEmpty ? null : double.parse(ph.text.trim()),
                                        'tds': tds.text.trim().isEmpty ? null : double.parse(tds.text.trim()),
                                        'device_uid': null,
                                      });

                                      if (!mounted) return;
                                      Navigator.pop(ctx, true);
                                    } catch (e) {
                                      setSheet(() => saving = false);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Save failed: $e')),
                                      );
                                    }
                                  },
                            label: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (saved == true) {
      await _loadMeasurements();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Manual reading saved')));
    }
  }

  static Widget _numField(
    String label,
    TextEditingController c, {
    int? decimals,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        helperText: helper,
      ),
      validator: validator,
    );
  }

  static String? _optionalRange(String? v, double lo, double hi, String msgIfBad) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null;
    final n = double.tryParse(s);
    if (n == null) return 'Enter a number';
    if (n < lo || n > hi) return msgIfBad;
    return null;
  }

  // ==========================================================
  // EDIT TANK (single, correct, includes delete button)
  // ==========================================================
  Future<void> _openEditTank() async {
    final supa = Supabase.instance.client;

    // 1) Pull freshest values from DB
    final row = await supa
        .from('tanks')
        .select(
          'name, volume_liters, volume_gallons, water_type, image_url, '
          'ideal_temp_min, ideal_temp_max, ideal_ph_min, ideal_ph_max, '
          'ideal_tds_min, ideal_tds_max',
        )
        .eq('id', widget.tank.id)
        .maybeSingle();

    final dbName = (row?['name'] as String?) ?? widget.tank.name;
    final dbLiters =
        (row?['volume_liters'] as num?)?.toDouble() ?? widget.tank.volumeLiters;
    final dbGallons = (row?['volume_gallons'] as num?)?.toDouble() ??
        (dbLiters / 3.785411784);
    final dbWater =
        (row?['water_type'] as String?) ?? (widget.tank.waterType ?? 'freshwater');
    final dbImageUrl = (row?['image_url'] as String?) ?? widget.tank.imageUrl;

    // Temps stored as °F
    final currentTMinF = ((row?['ideal_temp_min'] as num?)?.toDouble()) ??
        (widget.tank.idealTempMin ?? _defaultIdealTempMinF);
    final currentTMaxF = ((row?['ideal_temp_max'] as num?)?.toDouble()) ??
        (widget.tank.idealTempMax ?? _defaultIdealTempMaxF);

    final currentPhMin = ((row?['ideal_ph_min'] as num?)?.toDouble()) ??
        (widget.tank.idealPhMin ?? _defaultIdealPhMin);
    final currentPhMax = ((row?['ideal_ph_max'] as num?)?.toDouble()) ??
        (widget.tank.idealPhMax ?? _defaultIdealPhMax);

    final currentTdsMin = ((row?['ideal_tds_min'] as num?)?.toDouble()) ??
        (widget.tank.idealTdsMin ?? _defaultIdealTdsMin);
    final currentTdsMax = ((row?['ideal_tds_max'] as num?)?.toDouble()) ??
        (widget.tank.idealTdsMax ?? _defaultIdealTdsMax);

    final name = TextEditingController(text: dbName);

    final initialDisplayVol = _useGallons ? dbGallons : dbLiters;
    final vol = TextEditingController(text: initialDisplayVol.toStringAsFixed(0));

    String water = dbWater;
    String? imageUrl = dbImageUrl;

    final displayTMin = _useFahrenheit ? currentTMinF : _fToC(currentTMinF);
    final displayTMax = _useFahrenheit ? currentTMaxF : _fToC(currentTMaxF);

    final tMin = TextEditingController(text: displayTMin.toStringAsFixed(1));
    final tMax = TextEditingController(text: displayTMax.toStringAsFixed(1));

    final pMin = TextEditingController(text: currentPhMin.toString());
    final pMax = TextEditingController(text: currentPhMax.toString());
    final dMin = TextEditingController(text: currentTdsMin.toString());
    final dMax = TextEditingController(text: currentTdsMax.toString());

    final tempUnit = _useFahrenheit ? '°F' : '°C';
    final volumeLabel = _useGallons ? 'Volume (gal)' : 'Volume (L)';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final hasImage = (imageUrl != null && imageUrl!.trim().isNotEmpty);

            Future<void> handleDelete() async {
              final deleted = await _confirmAndDeleteTank();
              if (!deleted) return;

              if (!mounted) return;

              // Close sheet
              Navigator.pop(ctx, false);

              // Leave detail page (tank gone)
              Navigator.pop(context, true);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text(
                      'Edit Tank',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
  radius: 28,
  backgroundColor: Colors.grey.shade700,
  backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
  child: hasImage ? null : _logoAvatarFallback(size: 56),
),

                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final newUrl = await _pickAndUploadProfileImage(widget.tank.id);
                              if (newUrl != null) setSheet(() => imageUrl = newUrl);
                            },
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Change profile photo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _txt('Name', name),
                    const SizedBox(height: 10),
                    _txt(volumeLabel, vol, keyboard: TextInputType.number),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: water,
                      dropdownColor: const Color(0xFF0b1220),
                      decoration: const InputDecoration(
                        labelText: 'Water type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'freshwater', child: Text('Freshwater')),
                        DropdownMenuItem(value: 'saltwater', child: Text('Saltwater')),
                        DropdownMenuItem(value: 'brackish', child: Text('Brackish')),
                      ],
                      onChanged: (v) => setSheet(() => water = v ?? 'freshwater'),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Ideal ranges', style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _txt('Temp min ($tempUnit)', tMin, keyboard: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(child: _txt('Temp max ($tempUnit)', tMax, keyboard: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _txt('pH min', pMin, keyboard: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(child: _txt('pH max', pMax, keyboard: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _txt('TDS min', dMin, keyboard: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(child: _txt('TDS max', dMax, keyboard: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
  width: double.infinity,
  child: FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: _kDanger,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    icon: const Icon(Icons.delete_forever),
    label: const Text(
      'Delete tank',
      style: TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
    onPressed: handleDelete,
  ),
),

                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true) return;

    // Save back to DB (temps stored in °F)
    final volText = vol.text.trim();
    final parsedVol = double.tryParse(volText);
    final displayVol = parsedVol ?? initialDisplayVol;

    final gallons = _useGallons ? displayVol : (displayVol / 3.785411784);
    final liters = _useGallons ? (gallons * 3.785411784) : displayVol;

    double? idealTempMinF;
    double? idealTempMaxF;

    final parsedTMin = double.tryParse(tMin.text.trim());
    final parsedTMax = double.tryParse(tMax.text.trim());

    if (parsedTMin != null) {
      idealTempMinF = _useFahrenheit ? parsedTMin : _cToF(parsedTMin);
    }
    if (parsedTMax != null) {
      idealTempMaxF = _useFahrenheit ? parsedTMax : _cToF(parsedTMax);
    }

    await supa.from('tanks').update({
      'name': name.text.trim(),
      'volume_liters': liters,
      'volume_gallons': gallons,
      'water_type': water,
      'image_url': imageUrl?.trim(),
      'ideal_temp_min': idealTempMinF,
      'ideal_temp_max': idealTempMaxF,
      'ideal_ph_min': double.tryParse(pMin.text.trim()) ?? _defaultIdealPhMin,
      'ideal_ph_max': double.tryParse(pMax.text.trim()) ?? _defaultIdealPhMax,
      'ideal_tds_min': double.tryParse(dMin.text.trim()) ?? _defaultIdealTdsMin,
      'ideal_tds_max': double.tryParse(dMax.text.trim()) ?? _defaultIdealTdsMax,
    }).eq('id', widget.tank.id);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Tank updated')));

    setState(() {
      widget.tank.name = name.text.trim();
      widget.tank.volumeLiters = liters;
      widget.tank.waterType = water;
      widget.tank.imageUrl = imageUrl?.trim();
      widget.tank.idealTempMin = idealTempMinF;
      widget.tank.idealTempMax = idealTempMaxF;
      widget.tank.idealPhMin =
          double.tryParse(pMin.text.trim()) ?? _defaultIdealPhMin;
      widget.tank.idealPhMax =
          double.tryParse(pMax.text.trim()) ?? _defaultIdealPhMax;
      widget.tank.idealTdsMin =
          double.tryParse(dMin.text.trim()) ?? _defaultIdealTdsMin;
      widget.tank.idealTdsMax =
          double.tryParse(dMax.text.trim()) ?? _defaultIdealTdsMax;
    });

    await _loadMeasurements();
    if (mounted) setState(() {});
  }

  /// Confirmation + cascade delete for a tank (DB rows + storage).
  /// Returns true if deleted.
  Future<bool> _confirmAndDeleteTank() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete tank?'),
        content: const Text(
          'This will permanently delete this tank, its readings, notes, photos, and tasks. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return false;

    try {
      final supa = Supabase.instance.client;
      final tankId = widget.tank.id;

      // 1) tasks first (FK)
      await supa.from('tank_tasks').delete().eq('tank_id', tankId);

      // 2) readings
      await supa.from('sensor_readings').delete().eq('tank_id', tankId);

      // 3) notes + photos (delete storage first)
      final noteRows = await supa.from('tank_notes').select('id').eq('tank_id', tankId);
      final noteIds = (noteRows as List)
          .map((r) => r['id'] as String?)
          .whereType<String>()
          .toList();

      if (noteIds.isNotEmpty) {
        final photoRows = await supa
            .from('tank_note_photos')
            .select('storage_path')
            .inFilter('note_id', noteIds);

        final paths = (photoRows as List)
            .map((r) => (r['storage_path'] as String?) ?? '')
            .where((p) => p.trim().isNotEmpty)
            .toList();

        if (paths.isNotEmpty) {
          await supa.storage.from('tank-notes').remove(paths);
        }

        await supa.from('tank_note_photos').delete().inFilter('note_id', noteIds);
        await supa.from('tank_notes').delete().eq('tank_id', tankId);
      }

      // 4) finally delete tank
      await supa.from('tanks').delete().eq('id', tankId);

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted tank "${widget.tank.name}"')),
      );
      return true;
    } catch (e, st) {
      debugPrint('Delete tank failed: $e\n$st');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
      return false;
    }
  }

  static Widget _txt(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
      ),
    );
  }

  String _timeExact(DateTime t) {
    final date =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }

  String _lastMeasuredLabel() {
    final all = <DateTime>[
      if (latestTemp != null) latestTemp!.timestamp,
      if (latestPh != null) latestPh!.timestamp,
      if (latestTds != null) latestTds!.timestamp,
    ];
    if (all.isEmpty) return 'No data';
    final latest = all.reduce((a, b) => a.isAfter(b) ? a : b);
    var diff = DateTime.now().difference(latest);
    if (diff.isNegative) diff = Duration.zero;
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _labelForWaterType(String v) => switch (v) {
        'saltwater' => 'Saltwater',
        'brackish' => 'Brackish',
        _ => 'Freshwater',
      };

  String _labelForParam(ParamType t) =>
      t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';

  String _formatRange(RangeValues r) =>
      '${r.start.toStringAsFixed(1)} to ${r.end.toStringAsFixed(1)}';

  String _formatValue(ParameterReading r) {
    if (r.type == ParamType.ph) return r.value.toStringAsFixed(2);
    if (r.type == ParamType.tds) return r.value.toStringAsFixed(0);
    return r.value.toStringAsFixed(1);
  }

  // FIXED: correct Supabase Storage upload usage (no uploadBinary nonsense)
  Future<String?> _pickAndUploadProfileImage(String tankId) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (xfile == null) return null;

      final uid = Supabase.instance.client.auth.currentUser!.id;
      final id = const Uuid().v4();
      final ext = xfile.path.split('.').last.toLowerCase();
      final path = '$uid/tanks/$tankId/profile_$id.$ext';

      await Supabase.instance.client.storage.from('tank-images').upload(
            path,
            File(xfile.path),
            fileOptions: const FileOptions(upsert: true),
          );

      return Supabase.instance.client.storage.from('tank-images').getPublicUrl(path);
    } catch (e, st) {
      debugPrint('Upload failed: $e\n$st');
      if (!mounted) return null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      return null;
    }
  }
}

// ----------------------------- Models -----------------------------
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

  double get volumeGallons => volumeLiters / 3.785411784;
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
        id: (r['id'] as String?) ?? const Uuid().v4(),
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
        due: r['due_at'] == null ? null : DateTime.parse(r['due_at']).toLocal(),
        readingId: r['reading_id'],
      );
}

// ----------------------------- Card widget -----------------------------
class _MiniParameterCard extends StatelessWidget {
  const _MiniParameterCard({
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

    final valueStr = reading.value % 1 == 0
        ? reading.value.toInt().toString()
        : reading.type == ParamType.ph
            ? reading.value.toStringAsFixed(2)
            : reading.value.toStringAsFixed(1);

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
              Row(
                children: [
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
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$valueStr ${reading.unit}',
                style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.bold),
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
              decoration: const BoxDecoration(color: Color(0xFFE74C3C), shape: BoxShape.circle),
              child: const Center(
                child: Text('!', style: TextStyle(color: Colors.white, fontSize: 12, height: 1)),
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
