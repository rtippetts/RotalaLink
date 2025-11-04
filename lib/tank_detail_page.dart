/// ===============================================================
/// 🐠 Imports
/// ===============================================================

import 'dart:io'; // Gives access to local file operations (e.g., reading image files before uploading)
import 'package:flutter/material.dart'; // Provides Flutter’s Material Design widgets and UI components
import 'package:fl_chart/fl_chart.dart'; // Used for drawing line charts and graphs (for temperature, pH, TDS trends)
import 'package:image_picker/image_picker.dart'; // Lets the user take a photo or pick one from their gallery
import 'package:supabase_flutter/supabase_flutter.dart'; // Connects the app to Supabase for database, auth, and storage
import 'package:uuid/uuid.dart'; // Generates unique IDs (UUIDs) for naming uploaded images so filenames don’t collide


/// ===============================================================
/// 🐠 Tank Detail Page
/// ===============================================================
/// This class defines the **main screen** that shows details for a
/// single aquarium tank (Overview, Readings, Notes, Tasks, Photos).
///
/// 💾 Database: `sensor_readings`
///   Each reading record belongs to a tank and contains:
///     • tank_id (uuid) — which tank this data belongs to
///     • recorded_at (timestamptz) — when the measurement was taken
///     • temperature (double)
///     • ph (double)
///     • tds (int)
///
/// 🖼️ Storage: Supabase bucket `tank-images`
///   Folder structure for each user's photos:
///     <uid>/tanks/<tankId>/<uuid>.jpg
///   - <uid> is the user’s unique Supabase ID
///   - <tankId> is the tank this photo belongs to
///   - <uuid>.jpg is the unique filename for each photo
///
/// This page is **stateful**, meaning its contents can change over
/// time (e.g., when new readings load or when the user uploads photos).
/// ===============================================================

class TankDetailPage extends StatefulWidget {
  // The `const` constructor creates a new instance of this widget.
  // `super.key` is a Flutter "identifier" used internally to track widgets efficiently.
  // `required this.tank` means the caller MUST pass in a `Tank` object when creating this page.
  const TankDetailPage({super.key, required this.tank});

  // This variable holds the specific `Tank` object that this page will display.
  // The Tank class (defined elsewhere) contains info like the tank’s id, name, volume, etc.
  final Tank tank;

  @override
  // Flutter calls `createState()` automatically when the widget is built.
  // It returns an instance of the *State class* that controls this widget's behavior.
  // The leading underscore (_) in `_TankDetailPageState` makes that class private
  // to this file — it can’t be used or accessed elsewhere.
  State<TankDetailPage> createState() => _TankDetailPageState();
}


class _TankDetailPageState extends State<TankDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Measurements
  bool _loading = true;
  List<MeasurePoint> _points = [];

  // Chart state
  ParamType _series = ParamType.temperature;
  Period _period = Period.days7;

  // Notes / Tasks (demo)
  final List<TankLog> _logs = [];
  final List<TaskItem> _tasks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadMeasurements();
  }

  Future<void> _loadMeasurements() async {
    try {
      final supa = Supabase.instance.client;
      final fromUtc = _periodFromDate(_period)?.toUtc().toIso8601String();

      // Apply filters BEFORE order(); avoid typing the builder to keep it generic
      var q = supa
          .from('sensor_readings')
          .select('recorded_at, temperature, ph, tds')
          .eq('tank_id', widget.tank.id);

      if (fromUtc != null) {
        q = q.gte('recorded_at', fromUtc);
      }

      final rows = await q.order('recorded_at', ascending: true);

      final pts = (rows as List)
          .map((r) => MeasurePoint(
        at: DateTime.parse(r['recorded_at']).toLocal(),
        tempC: (r['temperature'] as num?)?.toDouble(),
        ph: (r['ph'] as num?)?.toDouble(),
        tds: (r['tds'] as num?)?.toDouble(),
      ))
          .toList();

      setState(() {
        _points = pts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load failed: $e')));
    }
  }

  DateTime? _periodFromDate(Period p) {
    final now = DateTime.now();
    switch (p) {
      case Period.days7:
        return now.subtract(const Duration(days: 7));
      case Period.month1:
        return DateTime(now.year, now.month - 1, now.day);
      case Period.year1:
        return DateTime(now.year - 1, now.month, now.day);
      case Period.all:
        return null;
    }
  }

  // latest tiles
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

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF111827);
    final subtitle =
        '${widget.tank.volumeLiters.toStringAsFixed(0)} L • ${_labelForWaterType(widget.tank.waterType ?? 'freshwater')}';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.teal.shade400,
              backgroundImage: (widget.tank.imageUrl != null &&
                  widget.tank.imageUrl!.trim().isNotEmpty)
                  ? NetworkImage(widget.tank.imageUrl!)
                  : null,
              child: (widget.tank.imageUrl == null ||
                  widget.tank.imageUrl!.trim().isEmpty)
                  ? const Icon(Icons.water, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.tank.name,
                      overflow: TextOverflow.ellipsis,
                      style:
                      const TextStyle(color: Colors.white, fontSize: 16)),
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
              Tab(text: 'Photos'),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMeasurements,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverview(const Color(0xFF1f2937)),
                  _buildReadings(const Color(0xFF1f2937)),
                  _buildNotes(const Color(0xFF1f2937)),
                  _buildTasks(const Color(0xFF1f2937)),
                  _buildPhotos(const Color(0xFF1f2937)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------- Overview -----------------------------
  Widget _buildOverview(Color card) {
    final tiles =
    [latestTemp, latestPh, latestTds].whereType<ParameterReading>().toList();

    return SafeArea(
      bottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (tiles.isNotEmpty)
            Row(
              children: List.generate(tiles.length, (i) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 12),
                    child: _MiniParameterCard(reading: tiles[i]),
                  ),
                );
              }),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No recent measurements',
                  style: TextStyle(color: Colors.white70)),
            ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...[
                [ParamType.temperature, 'Temperature'],
                [ParamType.ph, 'pH'],
                [ParamType.tds, 'TDS'],
              ].map((e) => ChoiceChip(
                label: Text(e[1] as String),
                selected: _series == e[0] as ParamType,
                onSelected: (_) =>
                    setState(() => _series = e[0] as ParamType),
                selectedColor: Colors.teal.withOpacity(.25),
                labelStyle: const TextStyle(color: Colors.white),
                backgroundColor: const Color(0xFF263244),
              )),
              const SizedBox(width: 8),
              ...[
                [Period.days7, '7 days'],
                [Period.month1, '1 month'],
                [Period.year1, '1 year'],
                [Period.all, 'All time'],
              ].map((e) => ChoiceChip(
                label: Text(e[1] as String),
                selected: _period == e[0] as Period,
                onSelected: (_) async {
                  setState(() => _period = e[0] as Period);
                  setState(() => _loading = true);
                  await _loadMeasurements();
                },
                selectedColor: Colors.teal.withOpacity(.25),
                labelStyle: const TextStyle(color: Colors.white),
                backgroundColor: const Color(0xFF263244),
              )),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              height: 240,
              child: _loading
                  ? const Center(
                  child: CircularProgressIndicator(color: Colors.teal))
                  : _spotsFor(_series).isEmpty
                  ? const Center(
                  child: Text('No data for selected range/parameter',
                      style: TextStyle(color: Colors.white54)))
                  : LineChart(_buildSingleSeriesChartData(_series)),
            ),
          ),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _loadMeasurements,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  // ----------------------------- Readings -----------------------------
  Widget _buildReadings(Color card) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration:
          BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            height: 240,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : _spotsFor(_series).isEmpty
                ? const Center(
                child:
                Text('No data', style: TextStyle(color: Colors.white54)))
                : LineChart(_buildSingleSeriesChartData(_series)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _seriesPicker()),
            const SizedBox(width: 8),
            Expanded(child: _periodPicker()),
          ],
        ),
        const SizedBox(height: 12),
        ..._points.reversed.take(100).map((p) {
          return ListTile(
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
          );
        }),
      ],
    );
  }

  Widget _seriesPicker() => DropdownButtonFormField<ParamType>(
    value: _series,
    dropdownColor: const Color(0xFF0b1220),
    decoration: const InputDecoration(
      labelText: 'Series',
      labelStyle: TextStyle(color: Colors.white70),
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(
          value: ParamType.temperature, child: Text('Temperature')),
      DropdownMenuItem(value: ParamType.ph, child: Text('pH')),
      DropdownMenuItem(value: ParamType.tds, child: Text('TDS')),
    ],
    onChanged: (v) => setState(() => _series = v ?? _series),
  );

  Widget _periodPicker() => DropdownButtonFormField<Period>(
    value: _period,
    dropdownColor: const Color(0xFF0b1220),
    decoration: const InputDecoration(
      labelText: 'Period',
      labelStyle: TextStyle(color: Colors.white70),
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: Period.days7, child: Text('7 days')),
      DropdownMenuItem(value: Period.month1, child: Text('1 month')),
      DropdownMenuItem(value: Period.year1, child: Text('1 year')),
      DropdownMenuItem(value: Period.all, child: Text('All time')),
    ],
    onChanged: (v) async {
      setState(() => _period = v ?? _period);
      setState(() => _loading = true);
      await _loadMeasurements();
    },
  );

  // ----------------------------- Notes -----------------------------
  Widget _buildNotes(Color card) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final log in _logs)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration:
            BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.event_note, color: Colors.white70),
              title: Text(log.text, style: const TextStyle(color: Colors.white)),
              subtitle: Text(_timeExact(log.when),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: _addLog,
          icon: const Icon(Icons.add),
          label: const Text('Add Note'),
        ),
      ],
    );
  }

  // ----------------------------- Tasks -----------------------------
  Widget _buildTasks(Color card) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == _tasks.length) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: _addTask,
            icon: const Icon(Icons.add_task),
            label: const Text('Add Task'),
          );
        }
        final t = _tasks[i];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: CheckboxListTile(
            value: t.done,
            onChanged: (v) => setState(() => t.done = v ?? false),
            title: Text(t.title, style: const TextStyle(color: Colors.white)),
            subtitle: t.due == null
                ? null
                : Text('Due ${_timeExact(t.due!)}',
                style: const TextStyle(color: Colors.white70)),
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            activeColor: Colors.teal,
          ),
        );
      },
    );
  }

  // ----------------------------- Photos -----------------------------
  Widget _buildPhotos(Color card) {
    return _TankPhotos(
      tankId: widget.tank.id,
      bucket: 'tank-images',
      cardColor: card,
    );
  }

  // ----------------------------- Chart helpers -----------------------------
  DateTime get _periodStart {
    final custom = _periodFromDate(_period);
    final start =
        custom ?? (_points.isNotEmpty ? _points.first.at : DateTime.now());
    return DateTime(start.year, start.month, start.day);
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  double _xDay(DateTime d) =>
      d.difference(_periodStart).inMinutes / (60 * 24);

  String _mmddForTick(double x) {
    final dt = _periodStart.add(Duration(days: x.round()));
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$m/$d';
  }

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
    final color = switch (type) {
      ParamType.temperature => Colors.redAccent,
      ParamType.ph => Colors.blueAccent,
      ParamType.tds => Colors.greenAccent,
    };

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
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (maxX - minX) <= 7 ? 1 : ((maxX - minX) / 6).ceilToDouble(),
            getTitlesWidget: (x, _) => Text(_mmddForTick(x),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
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

  // ----------------------------- Edit Tank -----------------------------
  Future<void> _openEditTank() async {
    final name = TextEditingController(text: widget.tank.name);
    final vol = TextEditingController(
        text: widget.tank.volumeLiters.toStringAsFixed(0));
    String water = widget.tank.waterType ?? 'freshwater';
    final img = TextEditingController(text: widget.tank.imageUrl ?? '');
    final tMin =
    TextEditingController(text: (widget.tank.idealTempMin ?? 24).toString());
    final tMax =
    TextEditingController(text: (widget.tank.idealTempMax ?? 26).toString());
    final pMin =
    TextEditingController(text: (widget.tank.idealPhMin ?? 6.8).toString());
    final pMax =
    TextEditingController(text: (widget.tank.idealPhMax ?? 7.6).toString());
    final dMin =
    TextEditingController(text: (widget.tank.idealTdsMin ?? 120).toString());
    final dMax =
    TextEditingController(text: (widget.tank.idealTdsMax ?? 220).toString());

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
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
                const Text('Edit Tank',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _txt('Name', name),
                const SizedBox(height: 10),
                _txt('Volume (L)', vol, keyboard: TextInputType.number),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: water,
                  dropdownColor: const Color(0xFF0b1220),
                  decoration: const InputDecoration(
                      labelText: 'Water type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'freshwater', child: Text('Freshwater')),
                    DropdownMenuItem(value: 'saltwater', child: Text('Saltwater')),
                    DropdownMenuItem(value: 'brackish', child: Text('Brackish')),
                  ],
                  onChanged: (v) => water = v ?? 'freshwater',
                ),
                const SizedBox(height: 10),
                _txt('Profile image URL', img),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ideal ranges',
                      style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _txt('Temp min (°C)', tMin,
                          keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _txt('Temp max (°C)', tMax,
                          keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child:
                      _txt('pH min', pMin, keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child:
                      _txt('pH max', pMax, keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child:
                      _txt('TDS min', dMin, keyboard: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(
                      child:
                      _txt('TDS max', dMax, keyboard: TextInputType.number)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
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
                ]),
              ],
            ),
          ),
        );
      },
    );

    if (ok == true) {
      final supa = Supabase.instance.client;
      final liters = double.tryParse(vol.text.trim()) ?? widget.tank.volumeLiters;
      final gallons = liters / 3.785411784;

      await supa.from('tanks').update({
        'name': name.text.trim(),
        'volume_liters': liters,                 // if you have it
        'volume_gallons': gallons,               // if your schema uses gallons
        'water_type': water,
        'image_url': img.text.trim(),
        'ideal_temp_min': double.tryParse(tMin.text.trim()),
        'ideal_temp_max': double.tryParse(tMax.text.trim()),
        'ideal_ph_min': double.tryParse(pMin.text.trim()),
        'ideal_ph_max': double.tryParse(pMax.text.trim()),
        'ideal_tds_min': double.tryParse(dMin.text.trim()),
        'ideal_tds_max': double.tryParse(dMax.text.trim()),
      }).eq('id', widget.tank.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tank updated')));

      setState(() {
        widget.tank.name = name.text.trim();
        widget.tank.volumeLiters = liters;
        widget.tank.waterType = water;
        widget.tank.imageUrl = img.text.trim();
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
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }


  // ----------------------------- Small actions -----------------------------
  void _addLog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'What happened?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      setState(() =>
          _logs.insert(0, TankLog(when: DateTime.now(), text: controller.text.trim())));
    }
  }

  void _addTask() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Task'),
        content:
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Task title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      setState(() => _tasks.add(TaskItem(name.text.trim())));
    }
  }

  // ----------------------------- Helpers -----------------------------
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
    if (diff.inMinutes < 1) return 'Last measured: just now';
    if (diff.inMinutes < 60) return 'Last measured: ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last measured: ${diff.inHours}h ago';
    return 'Last measured: ${diff.inDays}d ago';
  }

  String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }
}

// ----------------------------- Photos widget -----------------------------
class _TankPhotos extends StatefulWidget {
  const _TankPhotos({
    required this.tankId,
    required this.bucket,
    required this.cardColor,
  });

  final String tankId;
  final String bucket;
  final Color cardColor;

  @override
  State<_TankPhotos> createState() => _TankPhotosState();
}

class _TankPhotosState extends State<_TankPhotos> {
  final _picker = ImagePicker();
  bool _busy = false;
  List<FileObject> _items = [];

  String get _prefix {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    return '$uid/tanks/${widget.tankId}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() => _busy = true);
      final list = await Supabase.instance.client.storage
          .from(widget.bucket)
          .list(path: _prefix);
      setState(() {
        _items = list;
        _busy = false;
      });
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load photos failed: $e')));
    }
  }

  Future<void> _add(bool fromCamera) async {
    try {
      final xfile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (xfile == null) return;

      setState(() => _busy = true);
      final id = const Uuid().v4();
      final ext = xfile.path.split('.').last.toLowerCase();
      final path = '$_prefix/$id.$ext';

      await Supabase.instance.client.storage
          .from(widget.bucket)
          .upload(path, File(xfile.path));

      await _load();
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _delete(FileObject obj) async {
    try {
      setState(() => _busy = true);
      await Supabase.instance.client.storage
          .from(widget.bucket)
          .remove(['$_prefix/${obj.name}']);
      await _load();
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _add(true),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Take photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _add(false),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Add from gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.teal),
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (_, i) {
              final obj = _items[i];
              final fullPath = '$_prefix/${obj.name}';
              final url = Supabase.instance.client.storage
                  .from(widget.bucket)
                  .getPublicUrl(fullPath);
              return Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(url, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: InkWell(
                      onTap: _busy ? null : () => _delete(obj),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child:
                        const Icon(Icons.delete, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
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

  final String id; // UUID in Supabase
  String name;
  double volumeLiters;
  String inhabitants; // legacy display
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
  MeasurePoint({required this.at, this.tempC, this.ph, this.tds});
  final DateTime at;
  final double? tempC;
  final double? ph;
  final double? tds;
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

class TankLog {
  final DateTime when;
  final String text;
  const TankLog({required this.when, required this.text});
}

class TaskItem {
  TaskItem(this.title, {this.done = false, this.due});
  final String title;
  bool done;
  DateTime? due;
}

// ----------------------------- UI widgets -----------------------------
class _MiniParameterCard extends StatelessWidget {
  const _MiniParameterCard({required this.reading});
  final ParameterReading reading;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(reading);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_iconFor(reading.type), color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _label(reading.type),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${reading.value % 1 == 0 ? reading.value.toInt() : reading.value.toStringAsFixed(reading.type == ParamType.ph ? 2 : 1)} ${reading.unit}',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static String _label(ParamType t) =>
      t == ParamType.temperature ? 'Temperature' : t == ParamType.ph ? 'pH' : 'TDS';

  static Color _statusColor(ParameterReading r) {
    final v = r.value;
    if (v >= r.goodRange.start && v <= r.goodRange.end) return Colors.tealAccent;
    final span = r.goodRange.end - r.goodRange.start;
    final lowerWarn = r.goodRange.start - 0.1 * span;
    final upperWarn = r.goodRange.end + 0.1 * span;
    if (v >= lowerWarn && v <= upperWarn) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  static IconData _iconFor(ParamType t) {
    switch (t) {
      case ParamType.temperature:
        return Icons.thermostat;
      case ParamType.ph:
        return Icons.science;
      case ParamType.tds:
        return Icons.bubble_chart;
    }
  }
}
