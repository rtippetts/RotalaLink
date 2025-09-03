import 'package:flutter/material.dart';

/// ----------------------------------------------
/// Tank Detail Page (RotalaLink style)
/// ----------------------------------------------
/// This page shows a single aquarium ("tank") with tabs for
/// Overview, Parameters, Devices, Logs, Dosing, and Charts.
///
/// It uses in-memory demo data. Wire it to your backend later.
/// Dark theme colors match prior pages: background 0xFF111827, card 0xFF1f2937.

class TankDetailPage extends StatefulWidget {
  const TankDetailPage({super.key, required this.tank});

  final Tank tank;

  @override
  State<TankDetailPage> createState() => _TankDetailPageState();
}

class _TankDetailPageState extends State<TankDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<ParameterReading> _readings; // latest-by-parameter
  late List<DeviceInfo> _devices;
  late List<TankLog> _logs;
  late List<DoseSchedule> _doses;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);

    // --- Demo data ---
    _readings = [
      ParameterReading(type: ParamType.temperature, value: 25.3, unit: '°C', goodRange: const RangeValues(24, 26), timestamp: DateTime.now().subtract(const Duration(hours: 2))),
      ParameterReading(type: ParamType.ph, value: 7.2, unit: 'pH', goodRange: const RangeValues(6.8, 7.6), timestamp: DateTime.now().subtract(const Duration(hours: 1))),
      ParameterReading(type: ParamType.tds, value: 180, unit: 'ppm', goodRange: const RangeValues(120, 220), timestamp: DateTime.now().subtract(const Duration(hours: 3))),
      ParameterReading(type: ParamType.nh3, value: 0, unit: 'ppm', goodRange: const RangeValues(0, 0.2), timestamp: DateTime.now().subtract(const Duration(days: 1))),
      ParameterReading(type: ParamType.no2, value: 0.05, unit: 'ppm', goodRange: const RangeValues(0, 0.2), timestamp: DateTime.now().subtract(const Duration(days: 1))),
      ParameterReading(type: ParamType.no3, value: 12, unit: 'ppm', goodRange: const RangeValues(5, 20), timestamp: DateTime.now().subtract(const Duration(days: 1))),
    ];

    _devices = [
      DeviceInfo(name: 'ESP32 Sensor Hub', type: 'Probe Bridge', status: DeviceStatus.online, lastSeen: DateTime.now().subtract(const Duration(minutes: 5))),
      DeviceInfo(name: 'AquaHeater 150W', type: 'Heater', status: DeviceStatus.online, lastSeen: DateTime.now().subtract(const Duration(minutes: 1))),
      DeviceInfo(name: 'Canister Filter FX4', type: 'Filter', status: DeviceStatus.offline, lastSeen: DateTime.now().subtract(const Duration(hours: 10))),
    ];

    _logs = [
      TankLog(when: DateTime.now().subtract(const Duration(hours: 6)), text: '25% water change. Vacuumed substrate.'),
      TankLog(when: DateTime.now().subtract(const Duration(days: 1, hours: 2)), text: 'Added 10 mL all-in-one fertilizer.'),
      TankLog(when: DateTime.now().subtract(const Duration(days: 2)), text: 'Cleaned filter intake.'),
    ];

    _doses = [
      DoseSchedule(name: 'All-in-One', amountMl: 10, cadence: 'Every other day', nextDue: DateTime.now().add(const Duration(days: 1))),
      DoseSchedule(name: 'Potassium', amountMl: 6, cadence: 'Weekly', nextDue: DateTime.now().add(const Duration(days: 5))),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF111827);
    final card = const Color(0xFF1f2937);

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
        actions: [
          IconButton(
            tooltip: 'Edit tank',
            onPressed: _onEditTank,
            icon: const Icon(Icons.edit),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.tealAccent,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Parameters'),
            Tab(text: 'Devices'),
            Tab(text: 'Logs'),
            Tab(text: 'Dosing'),
            Tab(text: 'Charts'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReading,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add),
        label: const Text('Add Reading'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildOverview(card),
            _buildParameters(card),
            _buildDevices(card),
            _buildLogs(card),
            _buildDosing(card),
            _buildCharts(card),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() {});
  }

  // ----------------------------- Overview -----------------------------
  Widget _buildOverview(Color card) {
    final latest = _readings;
    final subtitle = '${widget.tank.volumeLiters.toStringAsFixed(0)} L • ${widget.tank.inhabitants}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.aquarium, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.tank.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: latest
              .map((r) => SizedBox(
            width: 160,
            child: ParameterCard(reading: r),
          ))
              .toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _addReading,
                icon: const Icon(Icons.add),
                label: const Text('Add Reading'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _onEditTank,
                icon: const Icon(Icons.edit),
                label: const Text('Edit Tank'),
              ),
            ),
          ],
        )
      ],
    );
  }

  String _lastUpdatedText() {
    final latest = _readings.map((r) => r.timestamp).fold<DateTime?>(null, (prev, e) => prev == null || e.isAfter(prev) ? e : prev);
    if (latest == null) return 'No data';
    final diff = DateTime.now().difference(latest);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ----------------------------- Parameters -----------------------------
  Widget _buildParameters(Color card) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, i) {
        final r = _readings[i];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(_iconFor(r.type), color: _statusColor(r)),
            title: Text(paramLabel(r.type), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Updated ${_timeAgo(r.timestamp)} • Range ${r.goodRange.start}-${r.goodRange.end} ${r.unit}', style: const TextStyle(color: Colors.white70)),
            trailing: Text('${_fmt(r.value)} ${r.unit}', style: TextStyle(color: _statusColor(r), fontWeight: FontWeight.bold)),
            onTap: () => _addReading(prefilled: r.type),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: _readings.length,
    );
  }

  // ----------------------------- Devices -----------------------------
  Widget _buildDevices(Color card) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = _devices[i];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(Icons.memory, color: d.status == DeviceStatus.online ? Colors.tealAccent : Colors.orangeAccent),
            title: Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('${d.type} • ${d.status.name.toUpperCase()} • last seen ${_timeAgo(d.lastSeen)}', style: const TextStyle(color: Colors.white70)),
            trailing: IconButton(
              tooltip: 'Details',
              icon: const Icon(Icons.chevron_right, color: Colors.white70),
              onPressed: () {},
            ),
          ),
        );
      },
    );
  }

  // ----------------------------- Logs -----------------------------
  Widget _buildLogs(Color card) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final log in _logs)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.event_note, color: Colors.white70),
              title: Text(log.text, style: const TextStyle(color: Colors.white)),
              subtitle: Text(_timeExact(log.when), style: const TextStyle(color: Colors.white70)),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
          onPressed: _addLog,
          icon: const Icon(Icons.add),
          label: const Text('Add Log Entry'),
        ),
      ],
    );
  }

  // ----------------------------- Dosing -----------------------------
  Widget _buildDosing(Color card) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _doses.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == _doses.length) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
            onPressed: _addDose,
            icon: const Icon(Icons.add),
            label: const Text('Add Dosing Rule'),
          );
        }
        final d = _doses[i];
        return Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.science, color: Colors.white70),
            title: Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('${d.amountMl} mL • ${d.cadence}', style: const TextStyle(color: Colors.white70)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Next due', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text(_timeExact(d.nextDue), style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------------------- Charts -----------------------------
  Widget _buildCharts(Color card) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Trends (7 days)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                height: 180,
                decoration: BoxDecoration(color: const Color(0xFF0b1220), borderRadius: BorderRadius.circular(12)),
                child: const Center(
                  child: Text('Hook up fl_chart or your chart lib here', style: TextStyle(color: Colors.white54)),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ParamType.values
                    .map((t) => FilterChip(
                  label: Text(paramLabel(t)),
                  selected: true,
                  onSelected: (_) {},
                ))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------- Actions -----------------------------
  void _onEditTank() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Tank (demo)'),
        content: Text('Name: ${widget.tank.name}\nVolume: ${widget.tank.volumeLiters} L'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _addLog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Log Entry'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'What happened?')),
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

  void _addDose() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Dosing Rule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: amount, decoration: const InputDecoration(labelText: 'Amount (mL)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.isNotEmpty && double.tryParse(amount.text) != null) {
      setState(() {
        _doses.add(DoseSchedule(name: name.text.trim(), amountMl: double.parse(amount.text), cadence: 'Custom', nextDue: DateTime.now().add(const Duration(days: 3))));
      });
    }
  }

  void _addReading({ParamType? prefilled}) async {
    ParamType selected = prefilled ?? ParamType.temperature;
    final valueCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Reading', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<ParamType>(
                value: selected,
                dropdownColor: const Color(0xFF0b1220),
                items: ParamType.values
                    .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(paramLabel(t), style: const TextStyle(color: Colors.white)),
                ))
                    .toList(),
                onChanged: (v) => selected = v ?? selected,
                decoration: const InputDecoration(labelText: 'Parameter', labelStyle: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Value', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    final val = double.tryParse(valueCtrl.text);
    if (ok == true && val != null) {
      setState(() {
        final idx = _readings.indexWhere((r) => r.type == selected);
        final base = _readings[idx];
        _readings[idx] = base.copyWith(value: val, timestamp: DateTime.now());
        _logs.insert(0, TankLog(when: DateTime.now(), text: 'Added ${paramLabel(selected)} reading: ${_fmt(val)} ${base.unit}'));
      });
    }
  }

  // ----------------------------- Helpers -----------------------------
  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  String _timeExact(DateTime t) {
    final date = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }

  Color _statusColor(ParameterReading r) {
    final v = r.value;
    if (v >= r.goodRange.start && v <= r.goodRange.end) return Colors.tealAccent;
    // If within 10% outside the range: warn; else critical
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
      case ParamType.nh3:
        return Icons.warning_amber_rounded;
      case ParamType.no2:
        return Icons.bloodtype;
      case ParamType.no3:
        return Icons.grass;
    }
  }

  String _fmt(num n) {
    if (n % 1 == 0) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }
}

// ----------------------------- Models -----------------------------
class Tank {
  final String id;
  final String name;
  final double volumeLiters;
  final String inhabitants; // e.g., "Community • Neocaridina"

  const Tank({required this.id, required this.name, required this.volumeLiters, required this.inhabitants});
}

enum ParamType { temperature, ph, tds, nh3, no2, no3 }

String paramLabel(ParamType t) {
  switch (t) {
    case ParamType.temperature:
      return 'Temperature';
    case ParamType.ph:
      return 'pH';
    case ParamType.tds:
      return 'TDS';
    case ParamType.nh3:
      return 'Ammonia (NH₃)';
    case ParamType.no2:
      return 'Nitrite (NO₂⁻)';
    case ParamType.no3:
      return 'Nitrate (NO₃⁻)';
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

  ParameterReading copyWith({double? value, DateTime? timestamp}) => ParameterReading(
    type: type,
    value: value ?? this.value,
    unit: unit,
    goodRange: goodRange,
    timestamp: timestamp ?? this.timestamp,
  );
}

class DeviceInfo {
  final String name;
  final String type;
  final DeviceStatus status;
  final DateTime lastSeen;

  const DeviceInfo({required this.name, required this.type, required this.status, required this.lastSeen});
}

enum DeviceStatus { online, offline }

class TankLog {
  final DateTime when;
  final String text;

  const TankLog({required this.when, required this.text});
}

class DoseSchedule {
  final String name;
  final double amountMl;
  final String cadence; // e.g., Daily, Weekly, Every other day
  final DateTime nextDue;

  const DoseSchedule({required this.name, required this.amountMl, required this.cadence, required this.nextDue});
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
          Text('${reading.value % 1 == 0 ? reading.value.toInt() : reading.value.toStringAsFixed(2)} ${reading.unit}',
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Ideal: ${reading.goodRange.start}-${reading.goodRange.end} ${reading.unit}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 2),
          Text(_timeAgo(reading.timestamp), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

// ----------------------------- Demo Entry -----------------------------
/// Drop this widget somewhere to try the page quickly.
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
          id: 't1',
          name: 'Shrimp Paradise',
          volumeLiters: 75,
          inhabitants: 'Neocaridina • Community',
        ),
      ),
    );
  }
}
