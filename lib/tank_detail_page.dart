/// ===============================================================
/// Tank Detail Page (drop-in) — manual-reading FAB, persistent
/// warnings, editable manual readings, Notes+Photos, Tasks (CRUD)
/// ===============================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  Color _seriesColor(ParamType t) => switch (t) {
    ParamType.temperature => _kTempBlue,
    ParamType.ph => _kPhGreen,
    ParamType.tds => _kTdsPurple,
  };

  late final TabController _tabController = TabController(length: 4, vsync: this);

  bool _loading = true;
  List<MeasurePoint> _points = [];

  ParamType _series = ParamType.temperature;
  Period _period = Period.month1;

  // Persisted entities
  List<NoteItem> _notes = [];
  List<TaskItem> _tasks = [];

  // Track dismissed warnings for this session (reading timestamp + param)
  final Set<String> _dismissedWarningKeys = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

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
      tempC: (r['temperature'] as num?)?.toDouble(),
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
    return ParameterReading(
      type: ParamType.temperature,
      value: last.tempC!,
      unit: '°C',
      goodRange: RangeValues(
        widget.tank.idealTempMin ?? 24,
        widget.tank.idealTempMax ?? 26,
      ),
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
        widget.tank.idealPhMin ?? 6.8,
        widget.tank.idealPhMax ?? 7.6,
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
        widget.tank.idealTdsMin ?? 120,
        widget.tank.idealTdsMax ?? 220,
      ),
      timestamp: last.at,
    );
  }

  // ---------------- Notes ----------------
  Future<void> _loadNotes() async {
    final rows = await Supabase.instance.client
        .from('tank_notes')
        .select('id, title, body, created_at, updated_at, user_id, '
        'photos:tank_note_photos(id, storage_path, public_url, created_at)')
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
      setState(() => busy = true);
      final noteId = existing?.id ?? const Uuid().v4();
      // If creating a new note, upload now and keep staged.
      for (final xf in xfiles) {
        final ext = xf.path.split('.').last.toLowerCase();
        final pid = const Uuid().v4();
        final path = '$uid/tanks/${widget.tank.id}/notes/$noteId/$pid.$ext';
        await Supabase.instance.client.storage.from(bucket).upload(path, File(xf.path));
        final url = Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
        photos.add(NotePhoto(id: pid, storagePath: path, publicUrl: url));
      }
      setState(() => busy = false);
    }

    Future<void> deleteStagedPhoto(NotePhoto p) async {
      await Supabase.instance.client.storage.from(bucket).remove([p.storagePath]);
      photos.removeWhere((x) => x.storagePath == p.storagePath);
      setState(() {});
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
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(children: const [
                    Icon(Icons.event_note, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Note', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: body,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Details', border: OutlineInputBorder()),
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
                                child: Image.network(p.publicUrl, width: 90, height: 90, fit: BoxFit.cover),
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
                                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : () async { await addPhotos(); setSheet((){}); },
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Add photos'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.save),
                        onPressed: busy ? null : () async {
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
                            // Any new photos already uploaded -> add rows
                            final newOnes = photos.where((p) => !(existing.photos.map((e)=>e.storagePath).toSet()).contains(p.storagePath)).toList();
                            if (newOnes.isNotEmpty) {
                              await supa.from('tank_note_photos').insert([
                                for (final p in newOnes)
                                  {'note_id': existing.id, 'storage_path': p.storagePath, 'public_url': p.publicUrl}
                              ]);
                            }
                          }
                          if (!mounted) return;
                          Navigator.pop(ctx, true);
                        },
                        label: const Text('Save'),
                      ),
                    ),
                  ]),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    final supa = Supabase.instance.client;
    // delete photo files first
    if (n.photos.isNotEmpty) {
      await supa.storage.from('tank-notes').remove([for (final p in n.photos) p.storagePath]);
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

  Future<void> _createOrEditTask({TaskItem? existing, String? readingId, String? suggestedTitle}) async {
    final title = TextEditingController(text: existing?.title ?? suggestedTitle ?? '');
    DateTime? due = existing?.due;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Task' : 'Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(due == null ? 'No due date' : 'Due: ${_timeExact(due!)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(context: ctx, initialDate: due ?? now, firstDate: now.subtract(const Duration(days: 3650)), lastDate: now.add(const Duration(days: 3650)));
                    if (d == null) return;
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(due ?? now));
                    setSheet(() => due = DateTime(d.year, d.month, d.day, (t?.hour ?? 0), (t?.minute ?? 0)));
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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
    final subtitle =
        '${widget.tank.volumeLiters.toStringAsFixed(0)} L • ${_labelForWaterType(widget.tank.waterType ?? 'freshwater')}';

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
              child: hasAppBarImg ? null : const Icon(Icons.water_drop, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.tank.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
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
        bottom: const PreferredSize(preferredSize: Size.fromHeight(4), child: SizedBox(height: 4)),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.science), // test-tube vibe
        label: const Text('Add manual reading'),
        onPressed: _openManualReadingForm,
      ),
    );
  }

  // ---------- Overview ----------
  Widget _buildOverview(Color card) {
    final tiles =
    [latestTemp, latestPh, latestTds].whereType<ParameterReading>().toList();

    bool _oor(ParameterReading r) =>
        r.value < r.goodRange.start || r.value > r.goodRange.end;
    String _key(ParameterReading r) =>
        '${r.type.name}@${r.timestamp.toIso8601String()}';

    final tempOOR =
        latestTemp != null && _oor(latestTemp!) && !_dismissedWarningKeys.contains(_key(latestTemp!));
    final phOOR =
        latestPh != null && _oor(latestPh!) && !_dismissedWarningKeys.contains(_key(latestPh!));
    final tdsOOR =
        latestTds != null && _oor(latestTds!) && !_dismissedWarningKeys.contains(_key(latestTds!));

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
                    (reading.type == ParamType.tds && tdsOOR)); // <— badge EVEN IF selected
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

          // Warning banner (only for selected param, only if most-recent reading is out-of-range & not dismissed)
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
                '${_labelForParam(r.type)} out of range: ${_formatValue(r)} (${r.unit}). Target ${_formatRange(r.goodRange)}';

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
                  Row(children: const [
                    Icon(Icons.error_outline, color: _kDanger),
                    SizedBox(width: 8),
                    Text('Warning', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(text, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Dismiss warning?'),
                              content: const Text('Are you sure you want to dismiss this warning?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Dismiss')),
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
                          final title = 'Fix ${_labelForParam(r!.type)} (${_formatValue(r)} ${r.unit}) • Target ${_formatRange(r.goodRange)}';
                          // Link to most recent reading id for selected param:
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

          // Chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              height: 260,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : _spotsFor(_series).isEmpty
                  ? const Center(child: Text('No data for selected parameter', style: TextStyle(color: Colors.white54)))
                  : LineChart(_buildSingleSeriesChartData(_series)),
            ),
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            height: 260,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : _spotsFor(_series).isEmpty
                ? const Center(child: Text('No data', style: TextStyle(color: Colors.white54)))
                : LineChart(_buildSingleSeriesChartData(_series)),
          ),
        ),
        const SizedBox(height: 12),

        // period picker
        DropdownButtonFormField<Period>(
          value: _period,
          dropdownColor: const Color(0xFF0b1220),
          decoration: const InputDecoration(labelText: 'Period', labelStyle: TextStyle(color: Colors.white70), border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: Period.days7, child: Text('7 days')),
            DropdownMenuItem(value: Period.month1, child: Text('1 month')),
            DropdownMenuItem(value: Period.year1, child: Text('1 year')),
            DropdownMenuItem(value: Period.all, child: Text('All time')),
          ],
          onChanged: (v) async {
            setState(() => _period = v ?? _period);
            await _loadMeasurements();
            setState(() {});
          },
        ),
        const SizedBox(height: 12),

        ..._points.reversed.take(200).map((p) {
          final isManual = p.deviceUid == null;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              dense: true,
              textColor: Colors.white,
              iconColor: Colors.white70,
              leading: const Icon(Icons.timeline),
              title: Text(_timeExact(p.at)),
              subtitle: Text(
                'Temp: ${p.tempC?.toStringAsFixed(1) ?? '-'} °C   '
                    'pH: ${p.ph?.toStringAsFixed(2) ?? '-'}   '
                    'TDS: ${p.tds?.toStringAsFixed(0) ?? '-'} ppm',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: isManual
                  ? IconButton(
                tooltip: 'Edit manual reading',
                icon: const Icon(Icons.edit),
                onPressed: () => _editManualReading(p),
              )
                  : const SizedBox.shrink(),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _editManualReading(MeasurePoint p) async {
    final temp = TextEditingController(text: p.tempC?.toString() ?? '');
    final ph = TextEditingController(text: p.ph?.toString() ?? '');
    final tds = TextEditingController(text: p.tds?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit manual reading'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numField('Temperature (°C)', temp, helper: '0–50', validator: (v) => _optionalRange(v, 0, 50, '0–50 °C or blank')),
              const SizedBox(height: 8),
              _numField('pH', ph, decimals: 2, helper: '0–14', validator: (v) => _optionalRange(v, 0, 14, '0–14 or blank')),
              const SizedBox(height: 8),
              _numField('TDS (ppm)', tds, helper: '0–5000', validator: (v) => _optionalRange(v, 0, 5000, '0–5000 or blank')),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text('Recorded at: ${_timeExact(p.at)} (locked)', style: const TextStyle(fontSize: 12))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final anyEntered = temp.text.trim().isNotEmpty || ph.text.trim().isNotEmpty || tds.text.trim().isNotEmpty;
              if (!anyEntered) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one value.')));
                return;
              }
              if (!formKey.currentState!.validate()) return;
              await Supabase.instance.client.from('sensor_readings').update({
                'temperature': temp.text.trim().isEmpty ? null : double.parse(temp.text.trim()),
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

  // ---------- Notes UI ----------
  Widget _buildNotes(Color card) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._notes.map((n) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.event_note, color: Colors.white70),
            title: Text(n.title, style: const TextStyle(color: Colors.white)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (n.body.trim().isNotEmpty) Text(n.body, style: const TextStyle(color: Colors.white70)),
                if (n.photos.isNotEmpty) const SizedBox(height: 8),
                if (n.photos.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in n.photos.take(3))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(p.publicUrl, width: 70, height: 70, fit: BoxFit.cover),
                        ),
                      if (n.photos.length > 3)
                        Text('+${n.photos.length - 3} more', style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(_timeExact(n.createdAt), style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
        )),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
          onPressed: () => _createOrEditNote(),
          icon: const Icon(Icons.add),
          label: const Text('Add Note'),
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
        if (i == _tasks.length) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
            onPressed: () => _createOrEditTask(),
            icon: const Icon(Icons.add_task),
            label: const Text('Add Task'),
          );
        }
        final t = _tasks[i];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: CheckboxListTile(
            value: t.done,
            onChanged: (v) async {
              await Supabase.instance.client.from('tank_tasks').update({'done': v ?? false}).eq('id', t.id);
              await _loadTasks();
              if (mounted) setState(() {});
            },
            title: Text(t.title, style: const TextStyle(color: Colors.white)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.due != null)
                  Text('Due ${_timeExact(t.due!)}', style: const TextStyle(color: Colors.white70)),
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

  DateTime get _periodEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  double _xDay(DateTime d) => d.difference(_periodStart).inMinutes / (60 * 24);

  String _mmddForTick(double x) {
    final dt = _periodStart.add(Duration(days: x.round()));
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d';
  }

  RangeValues _goodRangeFor(ParamType type) => switch (type) {
    ParamType.temperature => RangeValues(widget.tank.idealTempMin ?? 24, widget.tank.idealTempMax ?? 26),
    ParamType.ph => RangeValues(widget.tank.idealPhMin ?? 6.8, widget.tank.idealPhMax ?? 7.6),
    ParamType.tds => RangeValues(widget.tank.idealTdsMin ?? 120, widget.tank.idealTdsMax ?? 220),
  };

  List<FlSpot> _spotsFor(ParamType type) {
    List<double?> ys;
    switch (type) {
      case ParamType.temperature:
        ys = _points.map((e) => e.tempC).toList();
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

    // y-axis bounds
    double? minY, maxY;
    if (spots.isNotEmpty) {
      final ys = spots.map((s) => s.y).toList();
      final lo = ys.reduce((a, b) => a < b ? a : b);
      final hi = ys.reduce((a, b) => a > b ? a : b);
      if (type == ParamType.ph) {
        final pad = 0.2;
        minY = (lo - pad).clamp(5.0, 14.0);
        maxY = (hi + pad).clamp(5.0, 14.0);
      } else {
        final pad = (hi - lo).abs() * 0.15 + 0.5;
        minY = lo - pad;
        maxY = hi + pad;
      }
    }

    final minX = 0.0;
    final maxX = _periodEnd.difference(_periodStart).inDays.toDouble();

    // Ideal band
    final band = _goodRangeFor(type);
    final shade = _kDanger.withOpacity(0.10);

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      lineBarsData: [
        LineChartBarData(spots: spots, isCurved: false, dotData: const FlDotData(show: true), color: color, barWidth: 2),
      ],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(y: band.start, color: _kDanger, strokeWidth: 1.5, dashArray: [4, 3]),
        HorizontalLine(y: band.end, color: _kDanger, strokeWidth: 1.5, dashArray: [4, 3]),
      ]),
      rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: [
        HorizontalRangeAnnotation(y1: (minY ?? band.start) - 9999, y2: band.start, color: shade),
        HorizontalRangeAnnotation(y1: band.end, y2: (maxY ?? band.end) + 9999, color: shade),
      ]),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (maxX - minX) <= 7 ? 1 : ((maxX - minX) / 6).ceilToDouble(),
            getTitlesWidget: (x, _) => Text(_mmddForTick(x), style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> pickDateTime() async {
            final d = await showDatePicker(context: ctx, initialDate: localWhen, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d == null) return;
            final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(localWhen));
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
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(children: const [Icon(Icons.science, color: Colors.white), SizedBox(width: 8), Text('Add manual reading', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
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
                    _numField('Temperature (°C)', temp, helper: '0–50', validator: (v) => _optionalRange(v, 0, 50, 'Enter 0–50 °C or leave blank')),
                    const SizedBox(height: 10),
                    _numField('pH', ph, decimals: 2, helper: '0–14', validator: (v) => _optionalRange(v, 0, 14, 'Enter 0–14 pH or leave blank')),
                    const SizedBox(height: 10),
                    _numField('TDS (ppm)', tds, helper: '0–5000', validator: (v) => _optionalRange(v, 0, 5000, 'Enter 0–5000 ppm or leave blank')),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                          onPressed: saving
                              ? null
                              : () async {
                            final anyEntered = temp.text.trim().isNotEmpty || ph.text.trim().isNotEmpty || tds.text.trim().isNotEmpty;
                            if (!anyEntered) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one parameter.')));
                              return;
                            }
                            if (!formKey.currentState!.validate()) return;

                            setSheet(() => saving = true);
                            try {
                              final supa = Supabase.instance.client;
                              await supa.from('sensor_readings').insert({
                                'tank_id': widget.tank.id,
                                'recorded_at': localWhen.toUtc().toIso8601String(),
                                'temperature': temp.text.trim().isEmpty ? null : double.parse(temp.text.trim()),
                                'ph': ph.text.trim().isEmpty ? null : double.parse(ph.text.trim()),
                                'tds': tds.text.trim().isEmpty ? null : double.parse(tds.text.trim()),
                                'device_uid': null, // manual
                              });
                              if (!mounted) return;
                              Navigator.pop(ctx, true);
                            } catch (e) {
                              setSheet(() => saving = false);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                            }
                          },
                          label: const Text('Save'),
                        ),
                      ),
                    ]),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual reading saved')));
    }
  }

  static Widget _numField(String label, TextEditingController c, {int? decimals, String? helper, String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label, helperText: helper),
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

  // ---------- Edit Tank ----------
  Future<void> _openEditTank() async {
    final name = TextEditingController(text: widget.tank.name);
    final vol = TextEditingController(text: widget.tank.volumeLiters.toStringAsFixed(0));
    String water = widget.tank.waterType ?? 'freshwater';
    String? imageUrl = widget.tank.imageUrl;

    final tMin = TextEditingController(text: (widget.tank.idealTempMin ?? 24).toString());
    final tMax = TextEditingController(text: (widget.tank.idealTempMax ?? 26).toString());
    final pMin = TextEditingController(text: (widget.tank.idealPhMin ?? 6.8).toString());
    final pMax = TextEditingController(text: (widget.tank.idealPhMax ?? 7.6).toString());
    final dMin = TextEditingController(text: (widget.tank.idealTdsMin ?? 120).toString());
    final dMax = TextEditingController(text: (widget.tank.idealTdsMax ?? 220).toString());

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final hasImage = (imageUrl != null && imageUrl!.trim().isNotEmpty);
            return Padding(
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Text('Edit Tank', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey.shade700,
                          backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
                          child: hasImage ? null : const Icon(Icons.water_drop, color: Colors.white),
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
                    _txt('Volume (L)', vol, keyboard: TextInputType.number),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: water,
                      dropdownColor: const Color(0xFF0b1220),
                      decoration: const InputDecoration(labelText: 'Water type', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'freshwater', child: Text('Freshwater')),
                        DropdownMenuItem(value: 'saltwater', child: Text('Saltwater')),
                        DropdownMenuItem(value: 'brackish', child: Text('Brackish')),
                      ],
                      onChanged: (v) => setSheet(() => water = v ?? 'freshwater'),
                    ),
                    const SizedBox(height: 16),
                    const Align(alignment: Alignment.centerLeft, child: Text('Ideal ranges', style: TextStyle(color: Colors.white70))),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _txt('Temp min (°C)', tMin, keyboard: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _txt('Temp max (°C)', tMax, keyboard: TextInputType.number)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _txt('pH min', pMin, keyboard: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _txt('pH max', pMax, keyboard: TextInputType.number)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _txt('TDS min', dMin, keyboard: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(child: _txt('TDS max', dMax, keyboard: TextInputType.number)),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                      const SizedBox(width: 8),
                      Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))),
                    ]),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok == true) {
      final supa = Supabase.instance.client;
      final liters = double.tryParse(vol.text.trim()) ?? widget.tank.volumeLiters;
      final gallons = liters / 3.785411784;

      await supa.from('tanks').update({
        'name': name.text.trim(),
        'volume_liters': liters,
        'volume_gallons': gallons,
        'water_type': water,
        'image_url': imageUrl?.trim(),
        'ideal_temp_min': double.tryParse(tMin.text.trim()),
        'ideal_temp_max': double.tryParse(tMax.text.trim()),
        'ideal_ph_min': double.tryParse(pMin.text.trim()),
        'ideal_ph_max': double.tryParse(pMax.text.trim()),
        'ideal_tds_min': double.tryParse(dMin.text.trim()),
        'ideal_tds_max': double.tryParse(dMax.text.trim()),
      }).eq('id', widget.tank.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tank updated')));

      setState(() {
        widget.tank.name = name.text.trim();
        widget.tank.volumeLiters = liters;
        widget.tank.waterType = water;
        widget.tank.imageUrl = imageUrl?.trim();
        widget.tank.idealTempMin = double.tryParse(tMin.text.trim());
        widget.tank.idealTempMax = double.tryParse(tMax.text.trim());
        widget.tank.idealPhMin = double.tryParse(pMin.text.trim());
        widget.tank.idealPhMax = double.tryParse(pMax.text.trim());
        widget.tank.idealTdsMin = double.tryParse(dMin.text.trim());
        widget.tank.idealTdsMax = double.tryParse(dMax.text.trim());
      });
    }
  }

  static Widget _txt(String label, TextEditingController c, {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
    );
  }

  String _timeExact(DateTime t) {
    final date = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
    if (diff.inMinutes < 1) return 'Last measured: just now';
    if (diff.inMinutes < 60) return 'Last measured: ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last measured: ${diff.inHours}h ago';
    return 'Last measured: ${diff.inDays}d ago';
  }

  String _labelForWaterType(String v) => switch (v) {
    'saltwater' => 'Saltwater',
    'brackish' => 'Brackish',
    _ => 'Freshwater',
  };

  String _labelForParam(ParamType t) => t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';
  String _formatRange(RangeValues r) => '${r.start.toStringAsFixed(1)}–${r.end.toStringAsFixed(1)}';
  String _formatValue(ParameterReading r) {
    if (r.type == ParamType.ph) return r.value.toStringAsFixed(2);
    if (r.type == ParamType.tds) return r.value.toStringAsFixed(0);
    return r.value.toStringAsFixed(1);
  }

  Future<String?> _pickAndUploadProfileImage(String tankId) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (xfile == null) return null;

      final uid = Supabase.instance.client.auth.currentUser!.id;
      final id = const Uuid().v4();
      final ext = xfile.path.split('.').last.toLowerCase();
      final path = '$uid/tanks/$tankId/profile_$id.$ext';

      await Supabase.instance.client.storage.from('tank-images').upload(path, File(xfile.path), fileOptions: const FileOptions(upsert: true));
      return Supabase.instance.client.storage.from('tank-images').getPublicUrl(path);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
  NotePhoto({required this.id, required this.storagePath, required this.publicUrl});

  factory NotePhoto.fromRow(Map<String, dynamic> r) => NotePhoto(
    id: r['id'] ?? const Uuid().v4(),
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
  NoteItem({required this.id, required this.title, required this.body, required this.createdAt, this.updatedAt, required this.userId, required this.photos});

  factory NoteItem.fromRow(Map<String, dynamic> r) => NoteItem(
    id: r['id'],
    title: r['title'] ?? '',
    body: r['body'] ?? '',
    createdAt: DateTime.parse(r['created_at']).toLocal(),
    updatedAt: r['updated_at'] == null ? null : DateTime.parse(r['updated_at']).toLocal(),
    userId: r['user_id'],
    photos: (r['photos'] as List? ?? []).map((p) => NotePhoto.fromRow(p)).toList(),
  );
}

class TaskItem {
  final String id;
  final String title;
  final bool done;
  final DateTime? due;
  final String? readingId;
  TaskItem({required this.id, required this.title, required this.done, this.due, this.readingId});

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
              Row(children: [
                Icon(_iconFor(reading.type), color: fg, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _label(reading.type),
                    style: TextStyle(color: labelColor, fontWeight: FontWeight.w600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${reading.value % 1 == 0 ? reading.value.toInt() : reading.value.toStringAsFixed(reading.type == ParamType.ph ? 2 : 1)} ${reading.unit}',
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
              child: const Center(child: Text('!', style: TextStyle(color: Colors.white, fontSize: 12, height: 1))),
            ),
          ),
      ],
    );
  }

  static String _label(ParamType t) => t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';
  static IconData _iconFor(ParamType t) => switch (t) {
    ParamType.temperature => Icons.thermostat,
    ParamType.ph => Icons.science,
    ParamType.tds => Icons.bubble_chart,
  };
}
