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

import 'offline_store.dart';
import 'theme/rotala_brand.dart';
import 'app_settings.dart';
import 'tank_parameters.dart';

class TankDetailPage extends StatefulWidget {
  const TankDetailPage({super.key, required this.tank});
  final Tank tank;

  @override
  State<TankDetailPage> createState() => _TankDetailPageState();
}

class _TankDetailPageState extends State<TankDetailPage>
    with SingleTickerProviderStateMixin {
  static const int _kMaxMeasurementsPerTank = 500;

  // Color scheme
  static const _kTempBlue = Color(0xFF2F80ED);
  static const _kPhGreen = Color(0xFF27AE60);
  static const _kTdsPurple = Color(0xFF9B51E0);
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
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

  Color _seriesColor(ParamType t) => specFor(t).color;

  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );

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
      _loadNotes().catchError((_) {}),
      _loadTasks().catchError((_) {}),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  // ---------------- Measurements ----------------
  Future<void> _loadMeasurements() async {
    final supa = Supabase.instance.client;
    final fromUtc = _periodFromDate(_period)?.toUtc().toIso8601String();

    final fields = [
      'id',
      'tank_id',
      'recorded_at',
      'device_uid',
      for (final spec in kTankParameterSpecs) spec.readingField,
    ].join(', ');

    List<Map<String, dynamic>> rows;
    try {
      await OfflineStore.instance.syncPending(supa);
      var q = supa
          .from('sensor_readings')
          .select(fields)
          .eq('tank_id', widget.tank.id);

      if (fromUtc != null) q = q.gte('recorded_at', fromUtc);

      final remote = await q.order('recorded_at', ascending: true);
      rows = (remote as List).cast<Map<String, dynamic>>();
      await OfflineStore.instance.cacheReadings(widget.tank.id, rows);
    } catch (_) {
      rows = await OfflineStore.instance.getCachedReadingsSince(
        widget.tank.id,
        fromUtc: fromUtc,
      );
    }

    _points =
        rows
            .map(
              (r) => MeasurePoint(
                id: r['id'] as String,
                at: DateTime.parse(r['recorded_at']).toLocal(),
                tempC:
                    (() {
                      final tempF = (r['temperature'] as num?)?.toDouble();
                      return tempF == null ? null : _fToC(tempF);
                    })(),
                ph: (r['ph'] as num?)?.toDouble(),
                tds: (r['tds'] as num?)?.toDouble(),
                values: valueMapFromReadingRow(r),
                deviceUid: r['device_uid'] as String?,
              ),
            )
            .toList();
  }

  Future<int> _fetchMeasurementCountForTank(String tankId) async {
    final supa = Supabase.instance.client;
    try {
      final rows = await supa
          .from('sensor_readings')
          .select('id')
          .eq('tank_id', tankId);
      return (rows as List).length;
    } catch (_) {
      return OfflineStore.instance.cachedReadingCount(tankId);
    }
  }

  Future<bool> _tankMeasurementLimitReached(String tankId) async {
    final count = await _fetchMeasurementCountForTank(tankId);
    return count >= _kMaxMeasurementsPerTank;
  }

  void _showMeasurementLimitMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Measurement limit reached for this tank. Please clear out older measurements before adding more.',
        ),
        backgroundColor: Colors.orangeAccent,
      ),
    );
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
  ParameterReading? latestFor(ParamType type) {
    final v = _points.where((p) => p.valueFor(type) != null);
    if (v.isEmpty) return null;
    final last = v.last;
    final spec = specFor(type);
    final rawValue = last.valueFor(type)!;

    return ParameterReading(
      type: type,
      value: spec.isTemperature && _useFahrenheit ? _cToF(rawValue) : rawValue,
      unit: spec.isTemperature ? (_useFahrenheit ? 'F' : 'C') : spec.unitLabel,
      goodRange: _goodRangeFor(type),
      timestamp: last.at,
    );
  }

  List<ParamType> get _trackedParams =>
      kTankParameterSpecs
          .where((spec) => widget.tank.isTracking(spec.type))
          .map((spec) => spec.type)
          .toList();

  ParameterReading? get latestTemp => latestFor(ParamType.temperature);
  ParameterReading? get latestPh => latestFor(ParamType.ph);
  ParameterReading? get latestTds => latestFor(ParamType.tds);
  // ---------------- Notes ----------------
  Future<void> _loadNotes() async {
    try {
      final rows = await Supabase.instance.client
          .from('tank_notes')
          .select(
            'id, title, body, created_at, updated_at, user_id, photos:tank_note_photos(id, storage_path, public_url, created_at)',
          )
          .eq('tank_id', widget.tank.id)
          .order('created_at', ascending: false);
      _notes =
          (rows as List)
              .map((r) => NoteItem.fromRow(r as Map<String, dynamic>))
              .toList();
    } catch (_) {}
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
        final url = Supabase.instance.client.storage
            .from(bucket)
            .getPublicUrl(path);
        photos.add(NotePhoto(id: pid, storagePath: path, publicUrl: url));
      }
      busy = false;
      if (mounted) setState(() {});
    }

    Future<void> deleteStagedPhoto(NotePhoto p) async {
      await Supabase.instance.client.storage.from(bucket).remove([
        p.storagePath,
      ]);
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
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSheet) => Padding(
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
                            validator:
                                (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Required'
                                        : null,
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
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                OutlinedButton.icon(
                                  onPressed:
                                      busy
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
                                  onPressed:
                                      busy
                                          ? null
                                          : () async {
                                            if (!formKey.currentState!
                                                .validate())
                                              return;

                                            final supa =
                                                Supabase.instance.client;
                                            final userId = uid;

                                            if (existing == null) {
                                              final noteId = const Uuid().v4();
                                              await supa
                                                  .from('tank_notes')
                                                  .insert({
                                                    'id': noteId,
                                                    'tank_id': widget.tank.id,
                                                    'user_id': userId,
                                                    'title': title.text.trim(),
                                                    'body': body.text.trim(),
                                                  });

                                              if (photos.isNotEmpty) {
                                                await supa
                                                    .from('tank_note_photos')
                                                    .insert([
                                                      for (final p in photos)
                                                        {
                                                          'note_id': noteId,
                                                          'storage_path':
                                                              p.storagePath,
                                                          'public_url':
                                                              p.publicUrl,
                                                        },
                                                    ]);
                                              }
                                            } else {
                                              await supa
                                                  .from('tank_notes')
                                                  .update({
                                                    'title': title.text.trim(),
                                                    'body': body.text.trim(),
                                                  })
                                                  .eq('id', existing.id);

                                              final existingPaths =
                                                  existing.photos
                                                      .map((e) => e.storagePath)
                                                      .toSet();
                                              final newOnes =
                                                  photos
                                                      .where(
                                                        (p) =>
                                                            !existingPaths
                                                                .contains(
                                                                  p.storagePath,
                                                                ),
                                                      )
                                                      .toList();
                                              if (newOnes.isNotEmpty) {
                                                await supa
                                                    .from('tank_note_photos')
                                                    .insert([
                                                      for (final p in newOnes)
                                                        {
                                                          'note_id':
                                                              existing.id,
                                                          'storage_path':
                                                              p.storagePath,
                                                          'public_url':
                                                              p.publicUrl,
                                                        },
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
      builder:
          (_) => AlertDialog(
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
      await supa.storage.from('tank-notes').remove([
        for (final p in n.photos) p.storagePath,
      ]);
      await supa.from('tank_note_photos').delete().eq('note_id', n.id);
    }
    await supa.from('tank_notes').delete().eq('id', n.id);
    await _loadNotes();
    if (mounted) setState(() {});
  }

  // ---------------- Tasks ----------------
  Future<void> _loadTasks() async {
    try {
      final rows = await Supabase.instance.client
          .from('tank_tasks')
          .select('id, title, done, due_at, reading_id, created_at, updated_at')
          .eq('tank_id', widget.tank.id)
          .order('created_at', ascending: false);
      _tasks =
          (rows as List)
              .map((r) => TaskItem.fromRow(r as Map<String, dynamic>))
              .toList();
    } catch (_) {}
  }

  Future<void> _createOrEditTask({
    TaskItem? existing,
    String? readingId,
    String? suggestedTitle,
  }) async {
    final title = TextEditingController(
      text: existing?.title ?? suggestedTitle ?? '',
    );
    DateTime? due = existing?.due;

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder: (ctx, setSheet) {
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
                      title: Text(
                        due == null
                            ? 'No due date'
                            : 'Due: ${_timeExact(due!)}',
                      ),
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
                          setSheet(
                            () =>
                                due = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  (t?.hour ?? 0),
                                  (t?.minute ?? 0),
                                ),
                          );
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
            },
          ),
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
      await supa
          .from('tank_tasks')
          .update({
            'title': title.text.trim(),
            'due_at': due?.toUtc().toIso8601String(),
          })
          .eq('id', existing.id);
    }

    await _loadTasks();
    if (mounted) setState(() {});
  }

  Future<void> _deleteTask(TaskItem t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
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
    final cs = Theme.of(context).colorScheme;
    final cardColor = cs.surfaceContainerHighest;
    final volumeLabel =
        _useGallons
            ? '${widget.tank.volumeGallons.toStringAsFixed(0)} gal'
            : '${widget.tank.volumeLiters.toStringAsFixed(0)} L';

    final subtitle =
        '$volumeLabel • ${_labelForWaterType(widget.tank.waterType ?? 'freshwater')}';

    final hasAppBarImg =
        (widget.tank.imageUrl != null &&
            widget.tank.imageUrl!.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.surfaceContainerHighest,
              backgroundImage:
                  hasAppBarImg ? NetworkImage(widget.tank.imageUrl!) : null,
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
                    style: TextStyle(color: cs.onSurface, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$subtitle  •  ${_lastMeasuredLabel()}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Edit tank',
            icon: Icon(Icons.edit, color: cs.onSurface),
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
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: RotalaColors.teal,
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
              color: RotalaColors.teal,
              backgroundColor: cs.surface,
              onRefresh: _refreshAll,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverview(cardColor),
                  _buildReadings(cardColor),
                  _buildNotes(cardColor),
                  _buildTasks(cardColor),
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

        buffer.writeln(
          [
            recordedLocal.toIso8601String(),
            recordedUtc.toIso8601String(),
            fmtNum(tempC, decimals: 2),
            fmtNum(tempF, decimals: 2),
            fmtNum(ph, decimals: 3),
            fmtNum(tds, decimals: 0),
            deviceUid ?? '',
          ].join(','),
        );
      }

      final dir = await getTemporaryDirectory();
      final safeTankName =
          widget.tank.name
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
        SnackBar(
          content: Text(
            'Exported ${list.length} readings for ${widget.tank.name}',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('CSV export failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  // ---------- Overview ----------
  Widget _buildOverview(Color card) {
    final cs = Theme.of(context).colorScheme;
    final tiles =
        _trackedParams.map(latestFor).whereType<ParameterReading>().toList();

    bool _oor(ParameterReading r) =>
        r.value < r.goodRange.start || r.value > r.goodRange.end;
    String _key(ParameterReading r) =>
        '${r.type.name}@${r.timestamp.toIso8601String()}';

    final warningMap = {
      for (final reading in tiles)
        reading.type:
            _oor(reading) && !_dismissedWarningKeys.contains(_key(reading)),
    };

    return SafeArea(
      bottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (tiles.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    tiles.map((reading) {
                      final selected = reading.type == _series;
                      final showBadge = warningMap[reading.type] ?? false;
                      final color = _seriesColor(reading.type);
                      return FilterChip(
                        selected: selected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showBadge) ...[
                              const Icon(
                                Icons.error_outline,
                                size: 14,
                                color: Color(0xFFE74C3C),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(_labelForParam(reading.type)),
                          ],
                        ),
                        selectedColor: RotalaColors.teal.withValues(
                          alpha: 0.25,
                        ),
                        checkmarkColor: cs.onSurface,
                        labelStyle: TextStyle(
                          color: selected ? cs.onSurface : color,
                        ),
                        backgroundColor: cs.surface,
                        side: BorderSide(
                          color:
                              selected
                                  ? RotalaColors.teal.withValues(alpha: 0.7)
                                  : color.withValues(alpha: 0.45),
                        ),
                        onSelected:
                            (_) => setState(() => _series = reading.type),
                      );
                    }).toList(),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No recent measurements',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 12),

          DropdownButtonFormField<Period>(
            value: _period,
            dropdownColor: cs.surface,
            decoration: InputDecoration(
              labelText: 'Time range',
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

          Builder(
            builder: (_) {
              final r = latestFor(_series);
              if (r == null) return const SizedBox.shrink();

              final isOOR =
                  (r.value < r.goodRange.start || r.value > r.goodRange.end);
              final k = '${r.type.name}@${r.timestamp.toIso8601String()}';
              if (!isOOR || _dismissedWarningKeys.contains(k))
                return const SizedBox.shrink();

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
                      children: [
                        const Icon(Icons.error_outline, color: _kDanger),
                        const SizedBox(width: 8),
                        Text(
                          'Warning',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.onSurface,
                            side: BorderSide(color: cs.outline),
                          ),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (_) => AlertDialog(
                                    title: const Text('Dismiss warning?'),
                                    content: const Text(
                                      'Are you sure you want to dismiss this warning?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        child: const Text('Dismiss'),
                                      ),
                                    ],
                                  ),
                            );
                            if (ok == true)
                              setState(() => _dismissedWarningKeys.add(k));
                          },
                          child: const Text('Dismiss'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () {
                            final title =
                                'Fix ${_labelForParam(r.type)} (${_formatValue(r)} ${r.unit}) • Target ${_formatRange(r.goodRange)}';
                            final readingId = _mostRecentReadingIdFor(_series);
                            _createOrEditTask(
                              suggestedTitle: title,
                              readingId: readingId,
                            );
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
            },
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 260,
              child:
                  _loading
                      ? const Center(
                        child: CircularProgressIndicator(color: Colors.teal),
                      )
                      : _spotsFor(_series).isEmpty
                      ? Center(
                        child: Text(
                          'No data for selected parameter',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                      : LineChart(_buildSingleSeriesChartData(_series)),
            ),
          ),
        ],
      ),
    );
  }

  String? _mostRecentReadingIdFor(ParamType t) {
    final v = _points.where((p) => p.valueFor(t) != null);
    if (v.isEmpty) return null;
    return v.last.id;
  }

  // ---------- Readings ----------
  Widget _buildReadings(Color card) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outline),
          ),
          onPressed: _openManualReadingForm,
          icon: const Icon(Icons.add_chart),
          label: const Text('Add Reading'),
        ),
        const SizedBox(height: 12),
        ..._points.reversed.take(200).map((p) {
          final isManual = p.deviceUid == null;
          final iconData = isManual ? Icons.edit_note : Icons.sensors;
          final iconColor = isManual ? RotalaColors.teal : cs.onSurfaceVariant;
          final readings =
              _trackedParams
                  .map((type) => _formatPointReading(p, type))
                  .whereType<String>()
                  .toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outline),
            ),
            child: ListTile(
              dense: true,
              textColor: cs.onSurface,
              iconColor: cs.onSurfaceVariant,
              leading: Icon(iconData, color: iconColor),
              title: Text(_timeExact(p.at)),
              subtitle: Text(
                readings.isEmpty
                    ? 'No tracked values recorded'
                    : readings.join('   '),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip:
                        isManual
                            ? 'Edit manual reading'
                            : 'Edit device reading',
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
    final specs =
        _trackedParams.isEmpty
            ? kTankParameterSpecs.where((spec) => spec.defaultTracked).toList()
            : _trackedParams.map(specFor).toList();
    final ctrls = <ParamType, TextEditingController>{
      for (final spec in specs)
        spec.type: TextEditingController(
          text: () {
            final value = p.valueFor(spec.type);
            if (value == null) return '';
            final displayValue =
                spec.isTemperature && _useFahrenheit ? _cToF(value) : value;
            return displayValue.toStringAsFixed(spec.decimals);
          }(),
        ),
    };
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit reading'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final spec in specs) ...[
                      _numField(
                        _fieldLabelForSpec(spec),
                        ctrls[spec.type]!,
                        decimals: spec.decimals,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recorded at: ${_timeExact(p.at)} (locked)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final anyEntered = ctrls.values.any(
                    (c) => c.text.trim().isNotEmpty,
                  );
                  if (!anyEntered) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter at least one value.'),
                      ),
                    );
                    return;
                  }
                  if (!formKey.currentState!.validate()) return;

                  final payload = <String, dynamic>{};
                  for (final spec in specs) {
                    final raw = ctrls[spec.type]!.text.trim();
                    if (raw.isEmpty) {
                      payload[spec.readingField] = null;
                      continue;
                    }
                    final parsed = double.tryParse(raw);
                    payload[spec.readingField] =
                        parsed == null
                            ? null
                            : (spec.isTemperature
                                ? (_useFahrenheit ? parsed : _cToF(parsed))
                                : parsed);
                  }

                  await Supabase.instance.client
                      .from('sensor_readings')
                      .update(payload)
                      .eq('id', p.id);

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
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete reading?'),
            content: const Text('This will permanently remove this reading.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(12),
            ),
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
                          Text(
                            '+${n.photos.length - 3} more',
                            style: const TextStyle(color: Colors.white54),
                          ),
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
                itemBuilder:
                    (_) => const [
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
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: CheckboxListTile(
            value: t.done,
            onChanged: (v) async {
              await Supabase.instance.client
                  .from('tank_tasks')
                  .update({'done': v ?? false})
                  .eq('id', t.id);
              await _loadTasks();
              if (mounted) setState(() {});
            },
            title: Text(t.title, style: const TextStyle(color: Colors.white)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.due != null)
                  Text(
                    'Due ${_timeExact(t.due!)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            activeColor: Colors.teal,
            secondary: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              onSelected: (v) {
                if (v == 'edit') _createOrEditTask(existing: t);
                if (v == 'delete') _deleteTask(t);
              },
              itemBuilder:
                  (_) => const [
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
    final start =
        custom ?? (_points.isNotEmpty ? _points.first.at : DateTime.now());
    return DateTime(start.year, start.month, start.day);
  }

  double _xDay(DateTime d) => d.difference(_periodStart).inMinutes / (60 * 24);

  String _mmddForTick(double x) {
    final dt = _periodStart.add(Duration(days: x.round()));
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d';
  }

  RangeValues _goodRangeFor(ParamType type) {
    final range = widget.tank.rangeFor(type);
    if (specFor(type).isTemperature && !_useFahrenheit) {
      return RangeValues(_fToC(range.start), _fToC(range.end));
    }
    return range;
  }

  List<FlSpot> _spotsFor(ParamType type) {
    final spots = <FlSpot>[];
    for (final point in _points) {
      final rawValue = point.valueFor(type);
      if (rawValue == null) continue;
      final displayValue =
          specFor(type).isTemperature && _useFahrenheit
              ? _cToF(rawValue)
              : rawValue;
      spots.add(FlSpot(_xDay(point.at), displayValue));
    }
    return spots;
  }

  LineChartData _buildSingleSeriesChartData(ParamType type) {
    final spots = _spotsFor(type);
    final color = _seriesColor(type);
    final spec = specFor(type);

    double? minY, maxY;
    if (spots.isNotEmpty) {
      final ys = spots.map((s) => s.y).toList();
      final lo = ys.reduce((a, b) => a < b ? a : b);
      final hi = ys.reduce((a, b) => a > b ? a : b);

      if (type == ParamType.ph) {
        const pad = 0.2;
        minY = (lo - pad).clamp(0.0, 14.0);
        maxY = (hi + pad).clamp(0.0, 14.0);
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
          HorizontalLine(
            y: band.start,
            color: _kDanger,
            strokeWidth: 1.5,
            dashArray: [4, 3],
          ),
          HorizontalLine(
            y: band.end,
            color: _kDanger,
            strokeWidth: 1.5,
            dashArray: [4, 3],
          ),
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
            interval:
                (maxX - minX) <= 7 ? 1 : ((maxX - minX) / 6).ceilToDouble(),
            getTitlesWidget:
                (x, _) => Text(
                  _mmddForTick(x),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget:
                (y, _) => Text(
                  y.toStringAsFixed(spec.decimals),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
    );
  }

  Future<void> _openManualReadingForm() async {
    final specs =
        _trackedParams.isEmpty
            ? kTankParameterSpecs.where((spec) => spec.defaultTracked).toList()
            : _trackedParams.map(specFor).toList();
    final ctrls = <ParamType, TextEditingController>{
      for (final spec in specs) spec.type: TextEditingController(),
    };
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
      builder:
          (ctx) => StatefulBuilder(
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
                setSheet(
                  () =>
                      localWhen = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        t.hour,
                        t.minute,
                      ),
                );
              }

              String whenLabel() {
                final y = localWhen.year.toString().padLeft(4, '0');
                final m = localWhen.month.toString().padLeft(2, '0');
                final d = localWhen.day.toString().padLeft(2, '0');
                final hh = localWhen.hour.toString().padLeft(2, '0');
                final mm = localWhen.minute.toString().padLeft(2, '0');
                return '$y-$m-$d - $hh:$mm (local)';
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onTap: pickDateTime,
                          leading: const Icon(
                            Icons.schedule,
                            color: Colors.white,
                          ),
                          title: Text(
                            whenLabel(),
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: const Icon(
                            Icons.edit_calendar,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final spec in specs) ...[
                          _numField(
                            _fieldLabelForSpec(spec),
                            ctrls[spec.type]!,
                            decimals: spec.decimals,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    saving
                                        ? null
                                        : () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                icon:
                                    saving
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                        : const Icon(Icons.save),
                                onPressed:
                                    saving
                                        ? null
                                        : () async {
                                          final anyEntered = ctrls.values.any(
                                            (c) => c.text.trim().isNotEmpty,
                                          );
                                          if (!anyEntered) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Enter at least one parameter.',
                                                ),
                                              ),
                                            );
                                            return;
                                          }
                                          if (!formKey.currentState!.validate())
                                            return;

                                          final limitReached =
                                              await _tankMeasurementLimitReached(
                                                widget.tank.id,
                                              );
                                          if (limitReached) {
                                            _showMeasurementLimitMessage();
                                            return;
                                          }

                                          setSheet(() => saving = true);
                                          try {
                                            final payload = <String, dynamic>{
                                              'id': const Uuid().v4(),
                                              'tank_id': widget.tank.id,
                                              'recorded_at':
                                                  localWhen
                                                      .toUtc()
                                                      .toIso8601String(),
                                              'device_uid': null,
                                            };

                                            for (final spec in specs) {
                                              final raw =
                                                  ctrls[spec.type]!.text.trim();
                                              if (raw.isEmpty) continue;
                                              final parsed = double.tryParse(
                                                raw,
                                              );
                                              if (parsed == null) continue;
                                              payload[spec.readingField] =
                                                  spec.isTemperature
                                                      ? (_useFahrenheit
                                                          ? parsed
                                                          : _cToF(parsed))
                                                      : parsed;
                                            }

                                            final result = await OfflineStore
                                                .instance
                                                .saveReading(
                                                  client:
                                                      Supabase.instance.client,
                                                  tankId: widget.tank.id,
                                                  payload: payload,
                                                );

                                            if (!mounted) return;
                                            Navigator.pop(ctx, true);
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  result ==
                                                          OfflineSaveResult
                                                              .synced
                                                      ? 'Reading added'
                                                      : 'Reading saved offline and will sync when you reconnect',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            setSheet(() => saving = false);
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Save failed: $e',
                                                ),
                                              ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Manual reading saved')));
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
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: false,
      ),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        helperText: helper,
      ),
      validator: validator,
    );
  }

  static String? _optionalRange(
    String? v,
    double lo,
    double hi,
    String msgIfBad,
  ) {
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
    final selectFields = <String>[
      'name',
      'volume_liters',
      'volume_gallons',
      'water_type',
      'image_url',
      ...kTankParameterSpecs.map((spec) => spec.trackingField),
      ...kTankParameterSpecs.expand((spec) => [spec.minField, spec.maxField]),
    ].join(', ');

    final row =
        await supa
            .from('tanks')
            .select(selectFields)
            .eq('id', widget.tank.id)
            .maybeSingle();

    final dbName = (row?['name'] as String?) ?? widget.tank.name;
    final dbLiters =
        (row?['volume_liters'] as num?)?.toDouble() ?? widget.tank.volumeLiters;
    final dbGallons =
        (row?['volume_gallons'] as num?)?.toDouble() ??
        (dbLiters / 3.785411784);
    final dbWater =
        (row?['water_type'] as String?) ??
        (widget.tank.waterType ?? 'freshwater');
    final dbImageUrl = (row?['image_url'] as String?) ?? widget.tank.imageUrl;

    final name = TextEditingController(text: dbName);
    final initialDisplayVol = _useGallons ? dbGallons : dbLiters;
    final vol = TextEditingController(
      text: initialDisplayVol.toStringAsFixed(0),
    );
    String water = dbWater;
    String? imageUrl = dbImageUrl;

    final tracking = <ParamType, bool>{
      for (final spec in kTankParameterSpecs)
        spec.type:
            (row?[spec.trackingField] as bool?) ??
            widget.tank.isTracking(spec.type),
    };
    final minCtrls = <ParamType, TextEditingController>{};
    final maxCtrls = <ParamType, TextEditingController>{};
    for (final spec in kTankParameterSpecs) {
      final range = widget.tank.rangeFor(spec.type);
      final minValue = (row?[spec.minField] as num?)?.toDouble() ?? range.start;
      final maxValue = (row?[spec.maxField] as num?)?.toDouble() ?? range.end;
      final displayMin =
          spec.isTemperature && !_useFahrenheit ? _fToC(minValue) : minValue;
      final displayMax =
          spec.isTemperature && !_useFahrenheit ? _fToC(maxValue) : maxValue;
      minCtrls[spec.type] = TextEditingController(
        text: displayMin.toStringAsFixed(spec.decimals),
      );
      maxCtrls[spec.type] = TextEditingController(
        text: displayMax.toStringAsFixed(spec.decimals),
      );
    }

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
            final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
            final activeSpecs =
                kTankParameterSpecs
                    .where((spec) => tracking[spec.type] ?? false)
                    .toList();

            Future<void> handleDelete() async {
              final deleted = await _confirmAndDeleteTank();
              if (!deleted) return;
              if (!mounted) return;
              Navigator.pop(ctx, false);
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
                          backgroundImage:
                              hasImage ? NetworkImage(imageUrl!) : null,
                          child:
                              hasImage ? null : _logoAvatarFallback(size: 56),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final newUrl = await _pickAndUploadProfileImage(
                                widget.tank.id,
                              );
                              if (newUrl != null)
                                setSheet(() => imageUrl = newUrl);
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
                        DropdownMenuItem(
                          value: 'freshwater',
                          child: Text('Freshwater'),
                        ),
                        DropdownMenuItem(
                          value: 'saltwater',
                          child: Text('Saltwater'),
                        ),
                        DropdownMenuItem(
                          value: 'brackish',
                          child: Text('Brackish'),
                        ),
                      ],
                      onChanged:
                          (v) => setSheet(() => water = v ?? 'freshwater'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Tracked parameters',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await showModalBottomSheet<void>(
                              context: ctx,
                              backgroundColor: const Color(0xFF1f2937),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                              builder: (managerCtx) {
                                return StatefulBuilder(
                                  builder: (managerCtx, setManagerState) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        top: 16,
                                        bottom:
                                            MediaQuery.of(
                                              managerCtx,
                                            ).viewInsets.bottom +
                                            16,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Manage tracked parameters',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Choose what shows up below. Tap a parameter card to edit its ideal range.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final spec
                                                  in kTankParameterSpecs)
                                                FilterChip(
                                                  avatar: Icon(
                                                    spec.icon,
                                                    size: 16,
                                                    color: spec.color,
                                                  ),
                                                  selected:
                                                      tracking[spec.type] ??
                                                      false,
                                                  label: Text(spec.label),
                                                  selectedColor: RotalaColors
                                                      .teal
                                                      .withValues(alpha: 0.25),
                                                  checkmarkColor: Colors.white,
                                                  labelStyle: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                  backgroundColor: const Color(
                                                    0xFF0b1220,
                                                  ),
                                                  side: BorderSide(
                                                    color: spec.color
                                                        .withValues(
                                                          alpha: 0.45,
                                                        ),
                                                  ),
                                                  onSelected: (selected) {
                                                    setManagerState(() {
                                                      tracking[spec.type] =
                                                          selected;
                                                    });
                                                    setSheet(() {});
                                                  },
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            width: double.infinity,
                                            child: FilledButton(
                                              onPressed:
                                                  () =>
                                                      Navigator.pop(managerCtx),
                                              child: const Text('Done'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );

                            setSheet(() {});
                          },
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Manage'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tap a tracked parameter to edit its ideal range.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (activeSpecs.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0b1220),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No tracked parameters yet',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Choose the parameters you care about most, then tap each one to set its target range.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () async {
                                await showModalBottomSheet<void>(
                                  context: ctx,
                                  backgroundColor: const Color(0xFF1f2937),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (managerCtx) {
                                    return StatefulBuilder(
                                      builder: (managerCtx, setManagerState) {
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            left: 16,
                                            right: 16,
                                            top: 16,
                                            bottom:
                                                MediaQuery.of(
                                                  managerCtx,
                                                ).viewInsets.bottom +
                                                16,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Manage tracked parameters',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Choose what shows up below. Tap a parameter card to edit its ideal range.',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  for (final spec
                                                      in kTankParameterSpecs)
                                                    FilterChip(
                                                      avatar: Icon(
                                                        spec.icon,
                                                        size: 16,
                                                        color: spec.color,
                                                      ),
                                                      selected:
                                                          tracking[spec.type] ??
                                                          false,
                                                      label: Text(spec.label),
                                                      selectedColor:
                                                          RotalaColors.teal
                                                              .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                      checkmarkColor:
                                                          Colors.white,
                                                      labelStyle:
                                                          const TextStyle(
                                                            color: Colors.white,
                                                          ),
                                                      backgroundColor:
                                                          const Color(
                                                            0xFF0b1220,
                                                          ),
                                                      side: BorderSide(
                                                        color: spec.color
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                      ),
                                                      onSelected: (selected) {
                                                        setManagerState(() {
                                                          tracking[spec.type] =
                                                              selected;
                                                        });
                                                        setSheet(() {});
                                                      },
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        managerCtx,
                                                      ),
                                                  child: const Text('Done'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );

                                setSheet(() {});
                              },
                              child: const Text('Choose parameters'),
                            ),
                          ],
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: activeSpecs.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 2.35,
                            ),
                        itemBuilder: (context, index) {
                          final spec = activeSpecs[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () async {
                                final minCtrl = minCtrls[spec.type]!;
                                final maxCtrl = maxCtrls[spec.type]!;

                                await showModalBottomSheet<void>(
                                  context: ctx,
                                  isScrollControlled: true,
                                  backgroundColor: const Color(0xFF1f2937),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (editorCtx) {
                                    return StatefulBuilder(
                                      builder: (editorCtx, setEditorState) {
                                        final sliderValues =
                                            _sliderValuesForSpec(
                                              spec,
                                              minCtrl,
                                              maxCtrl,
                                            );
                                        final sliderMin =
                                            _effectiveSliderMinForSpec(
                                              spec,
                                              minCtrl,
                                              maxCtrl,
                                            );
                                        final sliderMax =
                                            _effectiveSliderMaxForSpec(
                                              spec,
                                              minCtrl,
                                              maxCtrl,
                                            );
                                        final unit =
                                            spec.isTemperature
                                                ? (_useFahrenheit ? 'F' : 'C')
                                                : spec.unitLabel;
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            left: 16,
                                            right: 16,
                                            top: 16,
                                            bottom:
                                                MediaQuery.of(
                                                  editorCtx,
                                                ).viewInsets.bottom +
                                                16,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color: spec.color
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      spec.icon,
                                                      color: spec.color,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          spec.label,
                                                          style:
                                                              const TextStyle(
                                                                color:
                                                                    Colors
                                                                        .white,
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          'Ideal range: ${_rangeSummaryText(spec, minCtrl, maxCtrl)}',
                                                          style: const TextStyle(
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFF0b1220,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'Min',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors
                                                                      .white54,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          TextField(
                                                            controller: minCtrl,
                                                            keyboardType:
                                                                const TextInputType.numberWithOptions(
                                                                  decimal: true,
                                                                ),
                                                            onChanged:
                                                                (_) =>
                                                                    setEditorState(
                                                                      () {},
                                                                    ),
                                                            style:
                                                                const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                            decoration: InputDecoration(
                                                              isDense: true,
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              suffixText:
                                                                  unit.isEmpty
                                                                      ? null
                                                                      : unit,
                                                              suffixStyle:
                                                                  const TextStyle(
                                                                    color:
                                                                        Colors
                                                                            .white,
                                                                    fontSize:
                                                                        18,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFF0b1220,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              14,
                                                            ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'Max',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors
                                                                      .white54,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          TextField(
                                                            controller: maxCtrl,
                                                            keyboardType:
                                                                const TextInputType.numberWithOptions(
                                                                  decimal: true,
                                                                ),
                                                            onChanged:
                                                                (_) =>
                                                                    setEditorState(
                                                                      () {},
                                                                    ),
                                                            style:
                                                                const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                            decoration: InputDecoration(
                                                              isDense: true,
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              suffixText:
                                                                  unit.isEmpty
                                                                      ? null
                                                                      : unit,
                                                              suffixStyle:
                                                                  const TextStyle(
                                                                    color:
                                                                        Colors
                                                                            .white,
                                                                    fontSize:
                                                                        18,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              SliderTheme(
                                                data: SliderTheme.of(
                                                  editorCtx,
                                                ).copyWith(
                                                  activeTrackColor: spec.color,
                                                  inactiveTrackColor: spec.color
                                                      .withValues(alpha: 0.20),
                                                  thumbColor: spec.color,
                                                  overlayColor: spec.color
                                                      .withValues(alpha: 0.18),
                                                  rangeThumbShape:
                                                      const RoundRangeSliderThumbShape(
                                                        enabledThumbRadius: 8,
                                                      ),
                                                ),
                                                child: RangeSlider(
                                                  min: sliderMin,
                                                  max: sliderMax,
                                                  divisions:
                                                      _sliderDivisionsForSpec(
                                                        spec,
                                                      ),
                                                  labels: RangeLabels(
                                                    sliderValues.start
                                                        .toStringAsFixed(
                                                          spec.decimals,
                                                        ),
                                                    sliderValues.end
                                                        .toStringAsFixed(
                                                          spec.decimals,
                                                        ),
                                                  ),
                                                  values: sliderValues,
                                                  onChanged: (values) {
                                                    _writeSliderValues(
                                                      spec,
                                                      minCtrl,
                                                      maxCtrl,
                                                      values,
                                                    );
                                                    setEditorState(() {});
                                                  },
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    sliderMin.toStringAsFixed(
                                                      spec.decimals,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    sliderMax.toStringAsFixed(
                                                      spec.decimals,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton(
                                                  onPressed:
                                                      () => Navigator.pop(
                                                        editorCtx,
                                                      ),
                                                  child: const Text('Done'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );

                                setSheet(() {});
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: spec.color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: spec.color.withValues(alpha: 0.7),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: spec.color.withValues(
                                                alpha: 0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                            ),
                                            child: Icon(
                                              spec.icon,
                                              color: spec.color,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              spec.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _rangeSummaryText(
                                          spec,
                                          minCtrls[spec.type]!,
                                          maxCtrls[spec.type]!,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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
                          style: TextStyle(fontWeight: FontWeight.bold),
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

    final volText = vol.text.trim();
    final parsedVol = double.tryParse(volText);
    final displayVol = parsedVol ?? initialDisplayVol;
    final gallons = _useGallons ? displayVol : (displayVol / 3.785411784);
    final liters = _useGallons ? (gallons * 3.785411784) : displayVol;

    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'volume_liters': liters,
      'volume_gallons': gallons,
      'water_type': water,
      'image_url': imageUrl?.trim(),
    };
    for (final spec in kTankParameterSpecs) {
      payload[spec.trackingField] = tracking[spec.type] ?? false;
      final minRaw = minCtrls[spec.type]!.text.trim();
      final maxRaw = maxCtrls[spec.type]!.text.trim();
      final minParsed = double.tryParse(minRaw);
      final maxParsed = double.tryParse(maxRaw);
      payload[spec.minField] =
          minParsed == null
              ? null
              : (spec.isTemperature && !_useFahrenheit
                  ? _cToF(minParsed)
                  : minParsed);
      payload[spec.maxField] =
          maxParsed == null
              ? null
              : (spec.isTemperature && !_useFahrenheit
                  ? _cToF(maxParsed)
                  : maxParsed);
    }

    await supa.from('tanks').update(payload).eq('id', widget.tank.id);

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tank updated')));

    setState(() {
      widget.tank.name = name.text.trim();
      widget.tank.volumeLiters = liters;
      widget.tank.waterType = water;
      widget.tank.imageUrl = imageUrl?.trim();
      for (final spec in kTankParameterSpecs) {
        widget.tank.tracking[spec.type] = tracking[spec.type] ?? false;
        final minParsed = double.tryParse(minCtrls[spec.type]!.text.trim());
        final maxParsed = double.tryParse(maxCtrls[spec.type]!.text.trim());
        widget.tank.idealRanges[spec.type] = RangeValues(
          minParsed ?? spec.defaultMin,
          maxParsed ?? spec.defaultMax,
        );
        if (spec.type == ParamType.temperature) {
          widget.tank.idealTempMin =
              minParsed == null
                  ? null
                  : (_useFahrenheit ? minParsed : _cToF(minParsed));
          widget.tank.idealTempMax =
              maxParsed == null
                  ? null
                  : (_useFahrenheit ? maxParsed : _cToF(maxParsed));
        } else if (spec.type == ParamType.ph) {
          widget.tank.idealPhMin = minParsed;
          widget.tank.idealPhMax = maxParsed;
        } else if (spec.type == ParamType.tds) {
          widget.tank.idealTdsMin = minParsed;
          widget.tank.idealTdsMax = maxParsed;
        }
      }
    });

    await _loadMeasurements();
    if (mounted) setState(() {});
  }

  /// Confirmation + cascade delete for a tank (DB rows + storage).
  /// Returns true if deleted.
  Future<bool> _confirmAndDeleteTank() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dctx) => AlertDialog(
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
      final noteRows = await supa
          .from('tank_notes')
          .select('id')
          .eq('tank_id', tankId);
      final noteIds =
          (noteRows as List)
              .map((r) => r['id'] as String?)
              .whereType<String>()
              .toList();

      if (noteIds.isNotEmpty) {
        final photoRows = await supa
            .from('tank_note_photos')
            .select('storage_path')
            .inFilter('note_id', noteIds);

        final paths =
            (photoRows as List)
                .map((r) => (r['storage_path'] as String?) ?? '')
                .where((p) => p.trim().isNotEmpty)
                .toList();

        if (paths.isNotEmpty) {
          await supa.storage.from('tank-notes').remove(paths);
        }

        await supa
            .from('tank_note_photos')
            .delete()
            .inFilter('note_id', noteIds);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      return false;
    }
  }

  static Widget _txt(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      onChanged: onChanged,
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
    final all =
        _trackedParams
            .map(latestFor)
            .whereType<ParameterReading>()
            .map((reading) => reading.timestamp)
            .toList();
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

  String _labelForParam(ParamType t) => specFor(t).label;

  String _formatRange(RangeValues r) =>
      '${r.start.toStringAsFixed(1)} to ${r.end.toStringAsFixed(1)}';

  String _formatValue(ParameterReading r) =>
      r.value.toStringAsFixed(specFor(r.type).decimals);

  String _formatRangeInputValue(TankParameterSpec spec, String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) return '--';
    return value.toStringAsFixed(spec.decimals);
  }

  String _rangeSummaryText(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
  ) {
    final minText = _formatRangeInputValue(spec, minCtrl.text);
    final maxText = _formatRangeInputValue(spec, maxCtrl.text);
    final unit =
        spec.isTemperature ? (_useFahrenheit ? 'F' : 'C') : spec.unitLabel;
    return unit.isEmpty ? '$minText - $maxText' : '$minText - $maxText $unit';
  }

  double _sliderMinForSpec(TankParameterSpec spec) {
    if (!spec.isTemperature) return spec.editorMin;
    return _useFahrenheit ? spec.editorMin : _fToC(spec.editorMin);
  }

  double _sliderMaxForSpec(TankParameterSpec spec) {
    if (!spec.isTemperature) return spec.editorMax;
    return _useFahrenheit ? spec.editorMax : _fToC(spec.editorMax);
  }

  int _sliderDivisionsForSpec(TankParameterSpec spec) {
    if (!spec.isTemperature || _useFahrenheit) return spec.sliderDivisions;
    return ((_sliderMaxForSpec(spec) - _sliderMinForSpec(spec)) * 2).round();
  }

  double _effectiveSliderMinForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
  ) {
    final baseMin = _sliderMinForSpec(spec);
    final currentMin = double.tryParse(minCtrl.text.trim());
    final currentMax = double.tryParse(maxCtrl.text.trim());
    return [
      baseMin,
      currentMin,
      currentMax,
    ].whereType<double>().reduce((a, b) => a < b ? a : b);
  }

  double _effectiveSliderMaxForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
  ) {
    final baseMax = _sliderMaxForSpec(spec);
    final currentMin = double.tryParse(minCtrl.text.trim());
    final currentMax = double.tryParse(maxCtrl.text.trim());
    return [
      baseMax,
      currentMin,
      currentMax,
    ].whereType<double>().reduce((a, b) => a > b ? a : b);
  }

  RangeValues _sliderValuesForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
  ) {
    final sliderMin = _effectiveSliderMinForSpec(spec, minCtrl, maxCtrl);
    final sliderMax = _effectiveSliderMaxForSpec(spec, minCtrl, maxCtrl);
    final minValue = (double.tryParse(minCtrl.text.trim()) ?? sliderMin).clamp(
      sliderMin,
      sliderMax,
    );
    final maxValue = (double.tryParse(maxCtrl.text.trim()) ?? sliderMax).clamp(
      sliderMin,
      sliderMax,
    );
    final start = minValue <= maxValue ? minValue : maxValue;
    final end = maxValue >= minValue ? maxValue : minValue;
    return RangeValues(start.toDouble(), end.toDouble());
  }

  void _writeSliderValues(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
    RangeValues values,
  ) {
    minCtrl.text = values.start.toStringAsFixed(spec.decimals);
    maxCtrl.text = values.end.toStringAsFixed(spec.decimals);
  }

  String _fieldLabelForSpec(TankParameterSpec spec) {
    if (spec.isTemperature) {
      return '${spec.label} (${_useFahrenheit ? 'F' : 'C'})';
    }
    if (spec.unitLabel.isEmpty || spec.unitLabel == spec.label) {
      return spec.label;
    }
    return '${spec.label} (${spec.unitLabel})';
  }

  String? _formatPointReading(MeasurePoint point, ParamType type) {
    final value = point.valueFor(type);
    if (value == null) return null;
    final spec = specFor(type);
    final displayValue =
        spec.isTemperature && _useFahrenheit ? _cToF(value) : value;
    final unit =
        spec.isTemperature ? (_useFahrenheit ? 'F' : 'C') : spec.unitLabel;
    final valueText = displayValue.toStringAsFixed(spec.decimals);
    return unit.isEmpty || unit == spec.label
        ? '${spec.label}: $valueText'
        : '${spec.label}: $valueText $unit';
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

      await Supabase.instance.client.storage
          .from('tank-images')
          .upload(
            path,
            File(xfile.path),
            fileOptions: const FileOptions(upsert: true),
          );

      return Supabase.instance.client.storage
          .from('tank-images')
          .getPublicUrl(path);
    } catch (e, st) {
      debugPrint('Upload failed: $e\n$st');
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      return null;
    }
  }
}

// ----------------------------- Models -----------------------------
enum Period { days7, month1, year1, all }

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
    Map<ParamType, bool>? tracking,
    Map<ParamType, RangeValues>? idealRanges,
  }) : tracking = tracking ?? {},
       idealRanges = idealRanges ?? {};

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
  final Map<ParamType, bool> tracking;
  final Map<ParamType, RangeValues> idealRanges;

  double get volumeGallons => volumeLiters / 3.785411784;

  bool isTracking(ParamType type) =>
      tracking[type] ?? specFor(type).defaultTracked;

  RangeValues rangeFor(ParamType type) =>
      idealRanges[type] ??
      RangeValues(specFor(type).defaultMin, specFor(type).defaultMax);
}

class MeasurePoint {
  MeasurePoint({
    required this.id,
    required this.at,
    this.tempC,
    this.ph,
    this.tds,
    Map<ParamType, double?>? values,
    this.deviceUid,
  }) : values = values ?? {};

  final String id;
  final DateTime at;
  final double? tempC;
  final double? ph;
  final double? tds;
  final Map<ParamType, double?> values;
  final String? deviceUid;

  double? valueFor(ParamType type) => switch (type) {
    ParamType.temperature => tempC ?? values[type],
    ParamType.ph => ph ?? values[type],
    ParamType.tds => tds ?? values[type],
    _ => values[type],
  };
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
    updatedAt:
        r['updated_at'] == null
            ? null
            : DateTime.parse(r['updated_at']).toLocal(),
    userId: r['user_id'],
    photos:
        (r['photos'] as List? ?? []).map((p) => NotePhoto.fromRow(p)).toList(),
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
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? color : cs.surfaceContainerHighest;
    final fg = selected ? Colors.white : color;
    final labelColor = selected ? Colors.white70 : cs.onSurfaceVariant;

    final spec = specFor(reading.type);
    final valueStr = reading.value.toStringAsFixed(spec.decimals);

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

  static String _label(ParamType t) => specFor(t).label;

  static IconData _iconFor(ParamType t) => specFor(t).icon;
}
