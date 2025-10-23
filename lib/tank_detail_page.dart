import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// --------------------------------------------------------
/// Tank Detail Page — RotalaLink (Overview + Logs + Tasks)
/// --------------------------------------------------------
/// • Only Temperature, pH, TDS
/// • Trends chart (7 days) lives on Overview with toggles
/// • Logs unchanged
/// • Dosing -> Tasks (checkbox list)
/// • Powered by Supabase `measurements` table
///
/// Expected `measurements` columns:
///   tank_id (uuid), measured_at (timestamptz),
///   temperature_c (double), ph (double), tds_ppm (double)

class TankDetailPage extends StatefulWidget {
  const TankDetailPage({super.key, required this.tank});
  final Tank tank;

  @override
  State<TankDetailPage> createState() => _TankDetailPageState();
}

class _TankDetailPageState extends State<TankDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Supabase data
  bool _loading = true;
  List<MeasurePoint> _points = [];

  // toggle which series to show
  bool showTemp = true;
  bool showPh = true;
  bool showTds = true;

  // Logs & Tasks (local demo – keep your existing hooks if you have them)
  final List<TankLog> _logs = [
    TankLog(when: DateTime.now().subtract(const Duration(hours: 6)), text: '25% water change. Vacuumed substrate.'),
    TankLog(when: DateTime.now().subtract(const Duration(days: 1, hours: 2)), text: 'Added 10 mL all-in-one fertilizer.'),
  ];
  final List<TaskItem> _tasks = [
    TaskItem('Clean glass', due: DateTime.now().add(const Duration(days: 2))),
    TaskItem('Rinse filter media', due: DateTime.now().add(const Duration(days: 7))),
    TaskItem('Top-off water', due: DateTime.now().add(const Duration(days: 1))),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMeasurements(); // fetch 7-day window
  }

  Future<void> _loadMeasurements() async {
    try {
      final supabase = Supabase.instance.client;

      final fromDate =
      DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String();

      final rows = await supabase
          .from('measurements')
          .select('measured_at, temperature_c, ph, tds_ppm')
          .eq('tank_id', widget.tank.id)
          .gte('measured_at', fromDate)
          .order('measured_at', ascending: true);

      final pts = (rows as List)
          .map((r) => MeasurePoint(
        at: DateTime.parse(r['measured_at']).toLocal(),
        tempC: (r['temperature_c'] as num?)?.toDouble(),
        ph: (r['ph'] as num?)?.toDouble(),
        tds: (r['tds_ppm'] as num?)?.toDouble(),
      ))
          .toList();

      setState(() {
        _points = pts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- computed latest values for the overview tiles
  ParameterReading? get latestTemp {
    final v = _points.where((p) => p.tempC != null).toList();
    if (v.isEmpty) return null;
    final last = v.last;
    return ParameterReading(
      type: ParamType.temperature,
      value: last.tempC!,
      unit: '°C',
      goodRange: const RangeValues(24, 26),
      timestamp: last.at,
    );
  }

  ParameterReading? get latestPh {
    final v = _points.where((p) => p.ph != null).toList();
    if (v.isEmpty) return null;
    final last = v.last;
    return ParameterReading(
      type: ParamType.ph,
      value: last.ph!,
      unit: 'pH',
      goodRange: const RangeValues(6.8, 7.6),
      timestamp: last.at,
    );
  }

  ParameterReading? get latestTds {
    final v = _points.where((p) => p.tds != null).toList();
    if (v.isEmpty) return null;
    final last = v.last;
    return ParameterReading(
      type: ParamType.tds,
      value: last.tds!,
      unit: 'ppm',
      goodRange: const RangeValues(120, 220),
      timestamp: last.at,
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF111827);
    const card = Color(0xFF1f2937);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.teal.shade400,
              child: const Icon(Icons.water, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Text(widget.tank.name, style: const TextStyle(color: Colors.white)),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: SizedBox(height: 4),
        ),
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.tealAccent,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Logs'),
                Tab(text: 'Tasks'),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadMeasurements,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverview(card),
                    _buildLogs(card),
                    _buildTasks(card),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------- Overview -----------------------------
  Widget _buildOverview(Color card) {
    final tiles = [latestTemp, latestPh, latestTds].whereType<ParameterReading>().toList();
    final subtitle =
        '${widget.tank.volumeLiters.toStringAsFixed(0)} L • ${widget.tank.inhabitants}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // header
        Container(
          padding: const EdgeInsets.all(16),
          decoration:
          BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.water, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.tank.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              Text(_lastUpdatedText(), style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // summary tiles
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles
              .map((r) => SizedBox(width: 160, child: ParameterCard(reading: r)))
              .toList(),
        ),

        const SizedBox(height: 24),

        // Trends + toggles
        Container(
          padding: const EdgeInsets.all(16),
          decoration:
          BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trends (7 days)',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: _loading
                    ? const Center(
                    child: CircularProgressIndicator(color: Colors.teal))
                    : _points.isEmpty
                    ? const Center(
                    child: Text('No measurements yet',
                        style: TextStyle(color: Colors.white54)))
                    : LineChart(_buildChartData()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    selected: showTemp,
                    label: const Text('Temperature'),
                    onSelected: (v) => setState(() => showTemp = v),
                  ),
                  FilterChip(
                    selected: showPh,
                    label: const Text('pH'),
                    onSelected: (v) => setState(() => showPh = v),
                  ),
                  FilterChip(
                    selected: showTds,
                    label: const Text('TDS'),
                    onSelected: (v) => setState(() => showTds = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // quick actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: _loadMeasurements,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          ],
        )
      ],
    );
  }

  LineChartData _buildChartData() {
    final baseTs = _points.first.at.millisecondsSinceEpoch.toDouble();

    List<FlSpot> mk(List<double?> ys) {
      final spots = <FlSpot>[];
      for (int i = 0; i < _points.length; i++) {
        final y = ys[i];
        if (y == null) continue;
        final x = (_points[i].at.millisecondsSinceEpoch - baseTs) / 1000 / 3600; // hours
        spots.add(FlSpot(x, y));
      }
      return spots;
    }

    final tempSpots = mk(_points.map((e) => e.tempC).toList());
    final phSpots = mk(_points.map((e) => e.ph).toList());
    final tdsSpots = mk(_points.map((e) => e.tds).toList());

    final lines = <LineChartBarData>[];
    if (showTemp && tempSpots.isNotEmpty) {
      lines.add(LineChartBarData(spots: tempSpots, isCurved: true, dotData: FlDotData(show: false)));
    }
    if (showPh && phSpots.isNotEmpty) {
      lines.add(LineChartBarData(spots: phSpots, isCurved: true, dotData: FlDotData(show: false)));
    }
    if (showTds && tdsSpots.isNotEmpty) {
      lines.add(LineChartBarData(spots: tdsSpots, isCurved: true, dotData: FlDotData(show: false)));
    }

    return LineChartData(
      lineBarsData: lines,
      gridData: FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 24, // hours
            getTitlesWidget: (x, meta) =>
                Text('${x.toInt()}h', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (y, meta) =>
                Text(y.toStringAsFixed(0), style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
    );
  }

  String _lastUpdatedText() {
    final all = [
      if (latestTemp != null) latestTemp!.timestamp,
      if (latestPh != null) latestPh!.timestamp,
      if (latestTds != null) latestTds!.timestamp,
    ];
    if (all.isEmpty) return 'No data';
    final latest = all.reduce((a, b) => a.isAfter(b) ? a : b);
    final diff = DateTime.now().difference(latest);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ----------------------------- Logs -----------------------------
  Widget _buildLogs(Color card) {
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
              subtitle:
              Text(_timeExact(log.when), style: const TextStyle(color: Colors.white70)),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24)),
          onPressed: _addLog,
          icon: const Icon(Icons.add),
          label: const Text('Add Log Entry'),
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
                side: const BorderSide(color: Colors.white24)),
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

  // ----------------------------- Small actions -----------------------------
  void _addLog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Log Entry'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      setState(() {
        _logs.insert(0, TankLog(when: DateTime.now(), text: controller.text.trim()));
      });
    }
  }

  void _addTask() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Task'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Task title')),
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
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }
}

// ----------------------------- Models -----------------------------
class Tank {
  final String id; // must be the same UUID as in Supabase tanks table
  final String name;
  final double volumeLiters;
  final String inhabitants;

  const Tank({
    required this.id,
    required this.name,
    required this.volumeLiters,
    required this.inhabitants,
  });
}

class MeasurePoint {
  MeasurePoint({required this.at, this.tempC, this.ph, this.tds});
  final DateTime at;
  final double? tempC;
  final double? ph;
  final double? tds;
}

enum ParamType { temperature, ph, tds }

String paramLabel(ParamType t) {
  switch (t) {
    case ParamType.temperature:
      return 'Temperature';
    case ParamType.ph:
      return 'pH';
    case ParamType.tds:
      return 'TDS';
  }
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

// ----------------------------- Widgets -----------------------------
class ParameterCard extends StatelessWidget {
  const ParameterCard({super.key, required this.reading});
  final ParameterReading reading;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(reading);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(reading.type), color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paramLabel(reading.type),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${reading.value % 1 == 0 ? reading.value.toInt() : reading.value.toStringAsFixed(2)} ${reading.unit}',
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Ideal: ${reading.goodRange.start}-${reading.goodRange.end} ${reading.unit}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(_timeAgo(reading.timestamp),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Color _statusColor(ParameterReading r) {
    final v = r.value;
    if (v >= r.goodRange.start && v <= r.goodRange.end) return Colors.tealAccent;
    final span = r.goodRange.end - r.goodRange.start;
    final lowerWarn = r.goodRange.start - 0.1 * span;
    final upperWarn = r.goodRange.end + 0.1 * span;
    if (v >= lowerWarn && v <= upperWarn) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  IconData _iconFor(ParamType t) {
    switch (t) {
      case ParamType.temperature:
        return Icons.thermostat;
      case ParamType.ph:
        return Icons.science;
      case ParamType.tds:
        return Icons.bubble_chart;
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

// ----------------------------- Demo -----------------------------
// Use this demo with your "My Third Tank" UUID to test quickly
class TankDetailDemo extends StatelessWidget {
  const TankDetailDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111827),
        colorScheme: const ColorScheme.dark(primary: Colors.teal),
        inputDecorationTheme: const InputDecorationTheme(
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
          border: OutlineInputBorder(),
        ),
      ),
      home: TankDetailPage(
        tank: const Tank(
          // 👇 replace with the UUID of "My Third Tank" from your Supabase `tanks` table
          id: '691ae986-7002-47a9-9fb2-2e0288d88fb6',
          name: 'My Third Tank',
          volumeLiters: 75,
          inhabitants: 'Neocaridina • Community',
        ),
      ),
    );
  }
}
