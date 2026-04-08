import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'onboarding/walkthrough.dart';
import 'tank_detail_page.dart';
import 'tank_parameters.dart';
import 'widgets/app_scaffold.dart';
import 'app_settings.dart';
import 'offline_store.dart';
import 'tank_views.dart';
import 'theme/rotala_brand.dart';

final _supa = Supabase.instance.client;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum LayoutMode { grid2, list, cards }

class _HomePageState extends State<HomePage> {
  static const int _kMaxTanksPerUser = 10;
  static const int _kMaxMeasurementsPerTank = 500;

  late final Stream<List<Map<String, dynamic>>> _tankStream;

  bool _retryingTanks = false;

  // Pull-to-refresh tick to force rebuild if needed
  int _refreshTick = 0;

  final _picker = ImagePicker();
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  LayoutMode _layout = LayoutMode.grid2;
  List<Map<String, dynamic>> _latestTanks = const [];

  final List<_GlobalTask> _globalTasks = [];
  bool _loadingGlobalTasks = false;

  // ---------- Defaults for NEW tanks ----------
  static const double _defaultIdealTempMinC = 0.0;
  static const double _defaultIdealTempMaxC = 43.0;

  static const double _defaultIdealPhMin = 0.0;
  static const double _defaultIdealPhMax = 14.0;

  static const double _defaultIdealTdsMin = 0.0;
  static const double _defaultIdealTdsMax = 1500.0;

  @override
  void initState() {
    super.initState();

    _tankStream = _supa
        .from('tanks')
        .stream(primaryKey: ['id'])
        .order('created_at');

    AppSettings.load();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowWalkthrough(),
    );

    _loadLayoutMode();
    _loadCachedTanks();
    _syncOfflineQueue();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ----------------- UI helpers -----------------
  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static const double _kPillRadius = 18;

  InputDecoration _pillDeco(String label, {String? helper}) {
    final r = BorderRadius.circular(_kPillRadius);

    OutlineInputBorder none() => OutlineInputBorder(
      borderRadius: r,
      borderSide: BorderSide.none, // no gray outline when unfocused
    );

    OutlineInputBorder teal() => OutlineInputBorder(
      borderRadius: r,
      borderSide: const BorderSide(color: Colors.tealAccent, width: 1.2),
    );

    OutlineInputBorder err() => OutlineInputBorder(
      borderRadius: r,
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
    );

    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      helperText: helper,
      helperStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF0b1220),

      border: none(),
      enabledBorder: none(),
      disabledBorder: none(),

      focusedBorder: teal(),

      errorBorder: err(),
      focusedErrorBorder: err(),

      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  InputDecoration _rangeDeco(String label) => _pillDeco(label);

  String _specUnitLabel(TankParameterSpec spec, String tempUnit) {
    return spec.isTemperature ? tempUnit : spec.unitLabel;
  }

  String _formatRangeValue(TankParameterSpec spec, String raw) {
    final value = _tryParseDouble(raw);
    if (value == null) return '--';
    return value.toStringAsFixed(spec.decimals);
  }

  String _rangeSummaryText(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
    String tempUnit,
  ) {
    final minText = _formatRangeValue(spec, minCtrl.text);
    final maxText = _formatRangeValue(spec, maxCtrl.text);
    final unit = _specUnitLabel(spec, tempUnit);
    return unit.isEmpty ? '$minText - $maxText' : '$minText - $maxText $unit';
  }

  double _sliderMinForSpec(TankParameterSpec spec, bool useF) {
    if (!spec.isTemperature) return spec.editorMin;
    return useF ? spec.editorMin : _fToC(spec.editorMin);
  }

  double _sliderMaxForSpec(TankParameterSpec spec, bool useF) {
    if (!spec.isTemperature) return spec.editorMax;
    return useF ? spec.editorMax : _fToC(spec.editorMax);
  }

  int _sliderDivisionsForSpec(TankParameterSpec spec, bool useF) {
    if (!spec.isTemperature || useF) return spec.sliderDivisions;
    return ((_sliderMaxForSpec(spec, false) - _sliderMinForSpec(spec, false)) *
            2)
        .round();
  }

  double _effectiveSliderMinForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
    bool useF,
  ) {
    final baseMin = _sliderMinForSpec(spec, useF);
    final currentMin = _tryParseDouble(minCtrl.text);
    final currentMax = _tryParseDouble(maxCtrl.text);
    return [baseMin, currentMin, currentMax]
        .whereType<double>()
        .reduce((a, b) => a < b ? a : b);
  }

  double _effectiveSliderMaxForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
    bool useF,
  ) {
    final baseMax = _sliderMaxForSpec(spec, useF);
    final currentMin = _tryParseDouble(minCtrl.text);
    final currentMax = _tryParseDouble(maxCtrl.text);
    return [baseMax, currentMin, currentMax]
        .whereType<double>()
        .reduce((a, b) => a > b ? a : b);
  }

  RangeValues _sliderValuesForSpec(
    TankParameterSpec spec,
    TextEditingController minCtrl,
    TextEditingController maxCtrl,
    bool useF,
  ) {
    final sliderMin = _effectiveSliderMinForSpec(
      spec,
      minCtrl,
      maxCtrl,
      useF,
    );
    final sliderMax = _effectiveSliderMaxForSpec(
      spec,
      minCtrl,
      maxCtrl,
      useF,
    );
    final minValue = (_tryParseDouble(minCtrl.text) ?? sliderMin).clamp(
      sliderMin,
      sliderMax,
    );
    final maxValue = (_tryParseDouble(maxCtrl.text) ?? sliderMax).clamp(
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

  Future<void> _maybeShowWalkthrough() async {
    final seen = await WalkthroughScreen.hasSeen();
    if (seen || !mounted) return;

    await WalkthroughScreen.show(context);

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kWalkthroughSeenKey) ?? false)) {
      await WalkthroughScreen.markSeen();
    }
  }

  String _timeExactGlobal(DateTime t) {
    final date =
        '${t.year.toString().padLeft(4, '0')}/${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')}';
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }

  double _cToF(double c) => c * 9.0 / 5.0 + 32.0;
  double _fToC(double f) => (f - 32.0) * 5.0 / 9.0;

  double? _tryParseDouble(String s) => double.tryParse(s.trim());

  Future<void> _loadCachedTanks() async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return;

    final cached = await OfflineStore.instance.getCachedTanks(uid);
    if (!mounted || cached.isEmpty) return;

    setState(() {
      _latestTanks = cached;
    });
  }

  Future<void> _syncOfflineQueue() async {
    try {
      final changed = await OfflineStore.instance.syncPending(_supa);
      if (changed && mounted) {
        final uid = _supa.auth.currentUser?.id;
        if (uid != null) {
          final cached = await OfflineStore.instance.getCachedTanks(uid);
          setState(() {
            _latestTanks = cached;
            _refreshTick++;
          });
        }
      }
    } catch (_) {}
  }

  Future<int> _fetchTankCountForCurrentUser() async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return 0;

    try {
      final rows = await _supa.from('tanks').select('id').eq('user_id', uid);
      return (rows as List).length;
    } catch (_) {
      final cached = await OfflineStore.instance.getCachedTanks(uid);
      return cached.length;
    }
  }

  Future<int> _fetchMeasurementCountForTank(String tankId) async {
    try {
      final rows = await _supa
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

  void _showTankLimitMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'We are still in development and due to data limits, you cannot add more than 10 tanks at a time. Thank you for being a beta tester!',
        ),
        backgroundColor: Colors.orangeAccent,
      ),
    );
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

  Future<void> _retryLoadTanks() async {
    setState(() {
      _retryingTanks = true;
    });

    try {
      await _supa
          .from('tanks')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _retryingTanks = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retryingTanks = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _retryingTanks = false;
    });
  }

  Future<void> _refreshHome() async {
    await _syncOfflineQueue();
    await _retryLoadTanks();

    // refresh other "non-stream" data that people expect to update
    await _loadGlobalTasks();

    if (!mounted) return;
    setState(() {
      _refreshTick++;
    });
  }

  Future<void> _loadLayoutMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('home_layout_mode');

    if (!mounted) return;

    setState(() {
      switch (saved) {
        case 'list':
          _layout = LayoutMode.list;
          break;
        case 'cards':
          _layout = LayoutMode.cards;
          break;
        case 'grid2':
          _layout = LayoutMode.grid2;
          break;
        default:
          _layout = LayoutMode.grid2;
      }
    });
  }

  Future<void> _saveLayoutMode() async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (_layout) {
      case LayoutMode.list:
        value = 'list';
        break;
      case LayoutMode.cards:
        value = 'cards';
        break;
      case LayoutMode.grid2:
        value = 'grid2';
        break;
    }
    await prefs.setString('home_layout_mode', value);
  }

  Future<void> _loadGlobalTasks() async {
    final uid = _supa.auth.currentUser?.id;

    if (uid == null) {
      setState(() {
        _globalTasks.clear();
        _loadingGlobalTasks = false;
      });
      return;
    }

    setState(() => _loadingGlobalTasks = true);

    try {
      final rows = await _supa
          .from('tank_tasks')
          .select('id, title, done, due_at, created_at, tank_id')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final list =
          (rows as List)
              .map(
                (r) => _GlobalTask(
                  id: r['id'] as String,
                  title: (r['title'] ?? '') as String,
                  done: r['done'] == true,
                  due:
                      r['due_at'] == null
                          ? null
                          : DateTime.parse(r['due_at']).toLocal(),
                  tankId: r['tank_id'] as String?,
                ),
              )
              .toList();

      setState(() {
        _globalTasks
          ..clear()
          ..addAll(list);
        _loadingGlobalTasks = false;
      });
    } catch (_) {
      setState(() => _loadingGlobalTasks = false);
    }
  }

  Future<void> _createOrEditGlobalTask({_GlobalTask? existing}) async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to manage tasks')));
      return;
    }

    final title = TextEditingController(text: existing?.title ?? '');
    DateTime? due = existing?.due;

    final saved = await showDialog<bool>(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder: (ctx, setSheet) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1f2937),
                title: Text(
                  existing == null ? 'Add Task' : 'Edit Task',
                  style: const TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.tealAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.edit_calendar,
                        color: Colors.white70,
                      ),
                      title: Text(
                        due == null
                            ? 'No due date'
                            : 'Due: ${_timeExactGlobal(due!)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () async {
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
                                t?.hour ?? 0,
                                t?.minute ?? 0,
                              ),
                        );
                      },
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

    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title cannot be empty')));
      return;
    }

    if (existing == null) {
      await _supa.from('tank_tasks').insert({
        'user_id': uid,
        'tank_id': null,
        'title': title.text.trim(),
        'done': false,
        'due_at': due?.toUtc().toIso8601String(),
      });
    } else {
      await _supa
          .from('tank_tasks')
          .update({
            'title': title.text.trim(),
            'due_at': due?.toUtc().toIso8601String(),
          })
          .eq('id', existing.id);
    }

    await _loadGlobalTasks();
  }

  Future<void> _deleteGlobalTask(_GlobalTask t) async {
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

    await _supa.from('tank_tasks').delete().eq('id', t.id);
    await _loadGlobalTasks();
  }

  Future<void> _openAddTaskSheet() async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return;

    final tanks = await _supa
        .from('tanks')
        .select('id,name')
        .order('created_at');

    String? selectedTankId;
    final titleCtrl = TextEditingController();
    DateTime? dueDate;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Add Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Task title',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedTankId,
                    dropdownColor: const Color(0xFF1f2937),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('General task'),
                      ),
                      for (final t in tanks)
                        DropdownMenuItem<String?>(
                          value: t['id'] as String,
                          child: Text(t['name'] ?? 'Tank'),
                        ),
                    ],
                    onChanged: (v) => setSheet(() => selectedTankId = v),
                    decoration: const InputDecoration(
                      labelText: 'Attach to tank',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueDate == null
                              ? 'No due date'
                              : 'Due: ${dueDate!.year}/${dueDate!.month.toString().padLeft(2, '0')}/${dueDate!.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.dark(),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setSheet(() => dueDate = picked);
                          }
                        },
                        child: const Text('Pick date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) return;

                      await _supa.from('tank_tasks').insert({
                        'user_id': uid,
                        'title': titleCtrl.text.trim(),
                        'tank_id': selectedTankId,
                        'done': false,
                        if (dueDate != null)
                          'due_at': dueDate!.toIso8601String(),
                      });

                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _openTankDetail(Tank tank) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TankDetailPage(tank: tank)),
    );
  }

  Tank _tankFromRow(Map<String, dynamic> row) {
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final rawImageUrl = (row['image_url'] as String?)?.trim();
    final imageUrl =
        (rawImageUrl == null || rawImageUrl.isEmpty || rawImageUrl == 'NULL')
            ? null
            : rawImageUrl;

    return Tank(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? 'Tank').toString(),
      volumeLiters: gallons * 3.785411784,
      inhabitants: ((row['water_type'] ?? 'freshwater') as String)
          .replaceFirstMapped(
            RegExp(r'^\w'),
            (match) => match.group(0)!.toUpperCase(),
          ),
      imageUrl: imageUrl,
      waterType: (row['water_type'] ?? 'freshwater').toString(),
      tracking: trackingMapFromRow(row),
      idealRanges: idealRangeMapFromRow(row),
    );
  }

  Future<void> _openTankSearch() async {
    await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: _TankSearchDelegate(tanks: _latestTanks),
    ).then((selected) {
      if (selected == null || !mounted) return;
      _openTankDetail(_tankFromRow(selected));
    });
  }

  IconData _iconForLayout(LayoutMode m) {
    switch (m) {
      case LayoutMode.cards:
        return Icons.view_agenda;
      case LayoutMode.list:
        return Icons.view_list;
      case LayoutMode.grid2:
        return Icons.grid_view;
    }
  }

  String _hintForNextLayout() {
    switch (_layout) {
      case LayoutMode.cards:
        return 'Switch to grid';
      case LayoutMode.list:
        return 'Switch to cards';
      case LayoutMode.grid2:
        return 'Switch to list';
    }
  }

  Future<void> _cycleLayout() async {
    setState(() {
      if (_layout == LayoutMode.grid2) {
        _layout = LayoutMode.list;
      } else if (_layout == LayoutMode.list) {
        _layout = LayoutMode.cards;
      } else {
        _layout = LayoutMode.grid2;
      }
    });

    await _saveLayoutMode();
  }

  Future<void> _openAssistantSheet() async {
    final input = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Assistant',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Ask about your tanks or devices',
                  hintStyle: TextStyle(color: Colors.white70),
                  prefixIcon: Icon(Icons.smart_toy, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTasksSheet() async {
    final uid = _supa.auth.currentUser?.id;

    if (uid == null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1f2937),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to view tasks',
              style: TextStyle(color: Colors.white70),
            ),
          );
        },
      );
      return;
    }

    await _loadGlobalTasks();

    final List<dynamic> tanks = await _supa
        .from('tanks')
        .select('id,name')
        .order('created_at');

    _TaskFilter filter = _TaskFilter.open;
    String? selectedTankId;

    final Set<String> pendingToggles = <String>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final cardColor = const Color(0xFF1f2937);

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (ctx, setSheet) {
                Future<void> refresh() async {
                  await _loadGlobalTasks();
                  setSheet(() {});
                }

                List<_GlobalTask> visible = List.of(_globalTasks);

                if (filter == _TaskFilter.open) {
                  visible = visible.where((t) => !t.done).toList();
                } else if (filter == _TaskFilter.completed) {
                  visible = visible.where((t) => t.done).toList();
                }

                if (selectedTankId != null) {
                  visible =
                      visible.where((t) => t.tankId == selectedTankId).toList();
                }

                Widget body;

                if (_loadingGlobalTasks) {
                  body = const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    ),
                  );
                } else if (visible.isEmpty) {
                  body = Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No tasks match your filters.',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            onPressed: () async {
                              await _createOrEditGlobalTask();
                              await refresh();
                            },
                            icon: const Icon(Icons.add_task),
                            label: const Text('Add Task'),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  body = Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: visible.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == visible.length) {
                          return OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                            ),
                            onPressed: () async {
                              await _createOrEditGlobalTask();
                              await refresh();
                            },
                            icon: const Icon(Icons.add_task),
                            label: const Text('Add Task'),
                          );
                        }

                        final t = visible[i];

                        final bool checkboxValue =
                            pendingToggles.contains(t.id) ? !t.done : t.done;

                        return Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CheckboxListTile(
                            value: checkboxValue,
                            onChanged: (v) async {
                              if (v == null) return;

                              setSheet(() {
                                pendingToggles.add(t.id);
                              });

                              try {
                                await Future.delayed(
                                  const Duration(milliseconds: 220),
                                );

                                await _supa
                                    .from('tank_tasks')
                                    .update({'done': v})
                                    .eq('id', t.id);

                                pendingToggles.remove(t.id);

                                await refresh();

                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      v
                                          ? 'Task marked complete'
                                          : 'Task reopened',
                                    ),
                                    duration: const Duration(seconds: 3),
                                    action: SnackBarAction(
                                      label: 'Undo',
                                      onPressed: () async {
                                        try {
                                          await _supa
                                              .from('tank_tasks')
                                              .update({'done': !v})
                                              .eq('id', t.id);
                                          await refresh();
                                        } catch (e) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not undo: $e',
                                              ),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                              } catch (e) {
                                pendingToggles.remove(t.id);
                                await refresh();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not update task: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                            title: Text(
                              t.title,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle:
                                t.due == null
                                    ? null
                                    : Text(
                                      'Due ${_timeExactGlobal(t.due!)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                            controlAffinity: ListTileControlAffinity.leading,
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            activeColor: Colors.teal,
                            secondary: PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white70,
                              ),
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await _createOrEditGlobalTask(existing: t);
                                  await refresh();
                                }
                                if (v == 'delete') {
                                  await _deleteGlobalTask(t);
                                  await refresh();
                                }
                              },
                              itemBuilder:
                                  (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.checklist, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text(
                          'Tasks',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.white),
                          onPressed: () async {
                            await _createOrEditGlobalTask();
                            await refresh();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedTankId,
                      dropdownColor: const Color(0xFF1f2937),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All tanks'),
                        ),
                        for (final t in tanks)
                          DropdownMenuItem<String?>(
                            value: t['id'] as String,
                            child: Text(t['name']?.toString() ?? 'Tank'),
                          ),
                      ],
                      onChanged: (v) {
                        selectedTankId = v;
                        setSheet(() {});
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Filter by tank',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          labelStyle: TextStyle(
                            color:
                                filter == _TaskFilter.all
                                    ? Colors.black
                                    : Colors.white70,
                          ),
                          selected: filter == _TaskFilter.all,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: const Color(0xFF0b1220),
                          onSelected: (_) {
                            filter = _TaskFilter.all;
                            setSheet(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Open'),
                          labelStyle: TextStyle(
                            color:
                                filter == _TaskFilter.open
                                    ? Colors.black
                                    : Colors.white70,
                          ),
                          selected: filter == _TaskFilter.open,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: const Color(0xFF0b1220),
                          onSelected: (_) {
                            filter = _TaskFilter.open;
                            setSheet(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Completed'),
                          labelStyle: TextStyle(
                            color:
                                filter == _TaskFilter.completed
                                    ? Colors.black
                                    : Colors.white70,
                          ),
                          selected: filter == _TaskFilter.completed,
                          selectedColor: Colors.tealAccent,
                          backgroundColor: const Color(0xFF0b1220),
                          onSelected: (_) {
                            filter = _TaskFilter.completed;
                            setSheet(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    body,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ------------------ UPDATED: Add Tank includes photo at top + no gray outlines ------------------
  Future<void> _openAddTankSheet() async {
    try {
      final tankCount = await _fetchTankCountForCurrentUser();
      if (tankCount >= _kMaxTanksPerUser) {
        _showTankLimitMessage();
        return;
      }
    } catch (_) {
      // If count check fails, continue to avoid blocking add flow on transient issues.
    }

    _pendingImageBytes = null;
    _pendingImageName = null;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final volumeCtrl = TextEditingController();
    String waterType = 'freshwater';
    final tracking = {
      for (final spec in kTankParameterSpecs) spec.type: spec.defaultTracked,
    };
    final minCtrls = {
      for (final spec in kTankParameterSpecs)
        spec.type: TextEditingController(
          text:
              spec.isTemperature
                  ? ''
                  : spec.defaultMin.toStringAsFixed(spec.decimals),
        ),
    };
    final maxCtrls = {
      for (final spec in kTankParameterSpecs)
        spec.type: TextEditingController(
          text:
              spec.isTemperature
                  ? ''
                  : spec.defaultMax.toStringAsFixed(spec.decimals),
        ),
    };

    bool lastUseF = AppSettings.useFahrenheit.value;

    if (lastUseF) {
      minCtrls[ParamType.temperature]!.text = _cToF(
        _defaultIdealTempMinC,
      ).toStringAsFixed(0);
      maxCtrls[ParamType.temperature]!.text = _cToF(
        _defaultIdealTempMaxC,
      ).toStringAsFixed(0);
    } else {
      minCtrls[ParamType.temperature]!.text = _defaultIdealTempMinC
          .toStringAsFixed(0);
      maxCtrls[ParamType.temperature]!.text = _defaultIdealTempMaxC
          .toStringAsFixed(0);
    }

    double? _tryD(TextEditingController c) => _tryParseDouble(c.text);

    void _syncTempFields(bool useF) {
      final minCtrl = minCtrls[ParamType.temperature]!;
      final maxCtrl = maxCtrls[ParamType.temperature]!;
      final minVal = _tryD(minCtrl);
      final maxVal = _tryD(maxCtrl);

      if (minVal != null) {
        final next = useF ? _cToF(minVal) : _fToC(minVal);
        minCtrl.text = next.toStringAsFixed(0);
      }
      if (maxVal != null) {
        final next = useF ? _cToF(maxVal) : _fToC(maxVal);
        maxCtrl.text = next.toStringAsFixed(0);
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Form(
                key: formKey,
                child: ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.useGallons,
                  builder: (context, useGallons, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: AppSettings.useFahrenheit,
                      builder: (context, useF, _) {
                        if (useF != lastUseF) {
                          _syncTempFields(useF);
                          lastUseF = useF;
                        }

                        final volumeLabel =
                            useGallons ? 'Volume (gallons)' : 'Volume (liters)';
                        final volumeHelper =
                            useGallons
                                ? 'Enter tank size in gallons'
                                : 'Enter tank size in liters';
                        final tempUnit = useF ? '°F' : '°C';

                        final trackedSpecs =
                            kTankParameterSpecs
                                .where((spec) => tracking[spec.type] ?? false)
                                .toList();

                        Future<void> openTrackingManager() async {
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
                                                label: Text(spec.label),
                                                selected:
                                                    tracking[spec.type] ??
                                                    false,
                                                selectedColor: RotalaColors.teal
                                                    .withValues(alpha: 0.25),
                                                checkmarkColor: Colors.white,
                                                labelStyle: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                                backgroundColor: const Color(
                                                  0xFF0b1220,
                                                ),
                                                side: BorderSide(
                                                  color: spec.color.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                ),
                                                onSelected: (selected) {
                                                  setManagerState(() {
                                                    tracking[spec.type] =
                                                        selected;
                                                  });
                                                  setStateSheet(() {});
                                                },
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed:
                                                () => Navigator.pop(managerCtx),
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

                          setStateSheet(() {});
                        }

                        Future<void> openRangeEditor(
                          TankParameterSpec spec,
                        ) async {
                          final minCtrl = minCtrls[spec.type]!;
                          final maxCtrl = maxCtrls[spec.type]!;
                          final unit = _specUnitLabel(spec, tempUnit);

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
                                  final sliderValues = _sliderValuesForSpec(
                                    spec,
                                    minCtrl,
                                    maxCtrl,
                                    useF,
                                  );
                                  final sliderMin =
                                      _effectiveSliderMinForSpec(
                                    spec,
                                    minCtrl,
                                    maxCtrl,
                                    useF,
                                  );
                                  final sliderMax =
                                      _effectiveSliderMaxForSpec(
                                    spec,
                                    minCtrl,
                                    maxCtrl,
                                    useF,
                                  );
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
                                                color: spec.color.withValues(
                                                  alpha: 0.16,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
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
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    spec.label,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Ideal range: ${_rangeSummaryText(spec, minCtrl, maxCtrl, tempUnit)}',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
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
                                                      BorderRadius.circular(14),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Min',
                                                      style: TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    TextField(
                                                      controller: minCtrl,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      onChanged:
                                                          (_) => setEditorState(
                                                            () {},
                                                          ),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                      decoration: InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            InputBorder.none,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        suffixText:
                                                            unit.isEmpty
                                                                ? null
                                                                : unit,
                                                        suffixStyle:
                                                            const TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontSize: 18,
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
                                                      BorderRadius.circular(14),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Max',
                                                      style: TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    TextField(
                                                      controller: maxCtrl,
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      onChanged:
                                                          (_) => setEditorState(
                                                            () {},
                                                          ),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                      decoration: InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            InputBorder.none,
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        suffixText:
                                                            unit.isEmpty
                                                                ? null
                                                                : unit,
                                                        suffixStyle:
                                                            const TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontSize: 18,
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
                                          data: SliderTheme.of(editorCtx)
                                              .copyWith(
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
                                                  useF,
                                                ),
                                            labels: RangeLabels(
                                              sliderValues.start
                                                  .toStringAsFixed(
                                                    spec.decimals,
                                                  ),
                                              sliderValues.end.toStringAsFixed(
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
                                                () => Navigator.pop(editorCtx),
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

                          setStateSheet(() {});
                        }

                        return SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Add Tank',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Beta limit: up to $_kMaxTanksPerUser tanks per account.',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),

                              _sectionHeader(
                                Icons.photo_camera_back,
                                'Photo (optional)',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () async {
                                      FocusScope.of(ctx).unfocus();
                                      await _pickFrom(
                                        ImageSource.gallery,
                                        setStateSheet,
                                      );
                                    },
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Gallery'),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton.icon(
                                    onPressed: () async {
                                      FocusScope.of(ctx).unfocus();
                                      await _pickFrom(
                                        ImageSource.camera,
                                        setStateSheet,
                                      );
                                    },
                                    icon: const Icon(Icons.photo_camera),
                                    label: const Text('Camera'),
                                  ),
                                ],
                              ),
                              if (_pendingImageBytes != null) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    _pendingImageBytes!,
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 18),

                              _sectionHeader(
                                Icons.info_outline,
                                'Tank details',
                              ),
                              const SizedBox(height: 10),

                              TextFormField(
                                controller: nameCtrl,
                                style: const TextStyle(color: Colors.white),
                                decoration: _pillDeco('Name'),
                                validator:
                                    (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Required'
                                            : null,
                              ),
                              const SizedBox(height: 12),

                              DropdownButtonFormField<String>(
                                value: waterType,
                                dropdownColor: const Color(0xFF1f2937),
                                style: const TextStyle(color: Colors.white),
                                decoration: _pillDeco('Water type'),
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
                                onChanged: (v) => waterType = v ?? 'freshwater',
                              ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: volumeCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(color: Colors.white),
                                decoration: _pillDeco(
                                  volumeLabel,
                                  helper: volumeHelper,
                                ),
                                validator: (v) {
                                  final n = _tryParseDouble(v ?? '');
                                  if (n == null || n <= 0) {
                                    return 'Enter a number greater than 0';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 18),

                              _sectionHeader(
                                Icons.checklist_rounded,
                                'Tracked parameters',
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Tap a tracked parameter to edit its ideal range.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: openTrackingManager,
                                    icon: const Icon(
                                      Icons.tune_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Manage'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (trackedSpecs.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0b1220),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        onPressed: openTrackingManager,
                                        child: const Text('Choose parameters'),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: trackedSpecs.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 10,
                                        crossAxisSpacing: 10,
                                        childAspectRatio: 2.35,
                                      ),
                                  itemBuilder: (context, index) {
                                    final spec = trackedSpecs[index];
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () => openRangeEditor(spec),
                                        child: Ink(
                                          decoration: BoxDecoration(
                                            color: spec.color.withValues(
                                              alpha: 0.10,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: spec.color.withValues(
                                                alpha: 0.7,
                                              ),
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
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 30,
                                                      height: 30,
                                                      decoration: BoxDecoration(
                                                        color: spec.color
                                                            .withValues(
                                                              alpha: 0.16,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              9,
                                                            ),
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
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w700,
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
                                                    tempUnit,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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

                              const SizedBox(height: 18),

                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed:
                                          () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () async {
                                        if (!formKey.currentState!.validate())
                                          return;

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Saving...'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );

                                        try {
                                          final uid =
                                              _supa.auth.currentUser!.id;
                                          final tankId = const Uuid().v4();
                                          final createdAt =
                                              DateTime.now()
                                                  .toUtc()
                                                  .toIso8601String();
                                          final tankCount =
                                              await _fetchTankCountForCurrentUser();
                                          if (tankCount >= _kMaxTanksPerUser) {
                                            if (mounted) {
                                              Navigator.pop(ctx, false);
                                              _showTankLimitMessage();
                                            }
                                            return;
                                          }

                                          String? imageUrl;
                                          String? pendingImageBase64;
                                          String imageExtension = 'jpg';
                                          if (_pendingImageBytes != null &&
                                              _pendingImageBytes!.isNotEmpty) {
                                            pendingImageBase64 = base64Encode(
                                              _pendingImageBytes!,
                                            );
                                            final parts = (_pendingImageName ??
                                                    '')
                                                .split('.');
                                            if (parts.length > 1) {
                                              imageExtension =
                                                  parts.last.toLowerCase();
                                            }
                                            try {
                                              imageUrl = await _uploadTankImage(
                                                _pendingImageBytes!,
                                              );
                                            } catch (_) {
                                              imageUrl = null;
                                            }
                                          }

                                          final raw = double.parse(
                                            volumeCtrl.text.trim(),
                                          );
                                          final useGallonsNow =
                                              AppSettings.useGallons.value;

                                          final double gallons;
                                          final double liters;

                                          if (useGallonsNow) {
                                            gallons = raw;
                                            liters = gallons * 3.785411784;
                                          } else {
                                            liters = raw;
                                            gallons = liters / 3.785411784;
                                          }

                                          final payload = <String, dynamic>{
                                            'id': tankId,
                                            'user_id': uid,
                                            'created_at': createdAt,
                                            'name': nameCtrl.text.trim(),
                                            'water_type': waterType,
                                            'volume_liters': liters,
                                            'volume_gallons': gallons,
                                            if (imageUrl != null)
                                              'image_url': imageUrl,
                                          };

                                          for (final spec
                                              in kTankParameterSpecs) {
                                            payload[spec.trackingField] =
                                                tracking[spec.type] ?? false;

                                            final minVal = _tryD(
                                              minCtrls[spec.type]!,
                                            );
                                            final maxVal = _tryD(
                                              maxCtrls[spec.type]!,
                                            );

                                            payload[spec.minField] =
                                                spec.isTemperature
                                                    ? (minVal == null
                                                        ? null
                                                        : (useF
                                                            ? minVal
                                                            : _cToF(minVal)))
                                                    : minVal;
                                            payload[spec.maxField] =
                                                spec.isTemperature
                                                    ? (maxVal == null
                                                        ? null
                                                        : (useF
                                                            ? maxVal
                                                            : _cToF(maxVal)))
                                                    : maxVal;
                                          }

                                          final result = await OfflineStore
                                              .instance
                                              .saveTank(
                                                client: _supa,
                                                userId: uid,
                                                payload: payload,
                                                pendingImageBase64:
                                                    pendingImageBase64,
                                                imageExtension: imageExtension,
                                              );

                                          if (mounted) {
                                            Navigator.pop(ctx, true);
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  result ==
                                                          OfflineSaveResult
                                                              .synced
                                                      ? 'Tank added'
                                                      : 'Tank saved offline and will sync when you reconnect',
                                                ),
                                              ),
                                            );
                                            await _loadCachedTanks();
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text('Failed: $e'),
                                                backgroundColor:
                                                    Colors.redAccent,
                                              ),
                                            );
                                          }
                                        }
                                      },
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
                  },
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) return;
  }

  Future<void> _openManualEntrySheet() async {
    try {
      final uid = _supa.auth.currentUser?.id;
      List<dynamic> tanks;
      try {
        await _syncOfflineQueue();
        tanks = await _supa
            .from('tanks')
            .select(
              'id,name,'
              'tracking_temperature,tracking_ph,tracking_ammonia,tracking_nitrite,tracking_nitrate,'
              'tracking_gh,tracking_kh,tracking_tds,tracking_co2,tracking_salinity,'
              'tracking_alkalinity,tracking_calcium,tracking_magnesium,tracking_phosphate',
            )
            .order('created_at');
      } catch (_) {
        tanks =
            uid == null
                ? const []
                : await OfflineStore.instance.getCachedTanks(uid);
      }
      if (!mounted) return;

      final tankRows = tanks.cast<Map<String, dynamic>>();
      String? tankId =
          tankRows.isNotEmpty ? tankRows.first['id'] as String : null;
      final valueCtrls = {
        for (final spec in kTankParameterSpecs)
          spec.type: TextEditingController(),
      };

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1f2937),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(
              builder: (ctx, setSheet) {
                if (tankRows.isEmpty) {
                  return const SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        'Add a tank before recording measurements.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }

                final selectedTank = tankRows.firstWhere(
                  (tank) => tank['id'] == tankId,
                  orElse: () => tankRows.first,
                );
                final tracking = trackingMapFromRow(selectedTank);
                final visibleSpecs =
                    kTankParameterSpecs
                        .where((spec) => tracking[spec.type] ?? false)
                        .toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add reading',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: tankId,
                      dropdownColor: const Color(0xFF1f2937),
                      items: [
                        for (final t in tankRows)
                          DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(t['name']?.toString() ?? 'Tank'),
                          ),
                      ],
                      onChanged: (v) => setSheet(() => tankId = v),
                      decoration: const InputDecoration(
                        labelText: 'Tank',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (visibleSpecs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'This tank is not tracking any parameters yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    for (final spec in visibleSpecs) ...[
                      if (spec.isTemperature)
                        ValueListenableBuilder<bool>(
                          valueListenable: AppSettings.useFahrenheit,
                          builder: (context, useFahrenheit, _) {
                            final unit = useFahrenheit ? 'F' : 'C';
                            return TextField(
                              controller: valueCtrls[spec.type],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '${spec.label} $unit',
                              ),
                            );
                          },
                        )
                      else
                        TextField(
                          controller: valueCtrls[spec.type],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                spec.unitLabel.isEmpty
                                    ? spec.label
                                    : '${spec.label} ${spec.unitLabel}',
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            tankId == null
                                ? null
                                : () async {
                                  try {
                                    final selectedTankId = tankId;
                                    if (selectedTankId == null) return;

                                    final limitReached =
                                        await _tankMeasurementLimitReached(
                                          selectedTankId,
                                        );
                                    if (limitReached) {
                                      _showMeasurementLimitMessage();
                                      return;
                                    }

                                    final payload = <String, dynamic>{
                                      'id': const Uuid().v4(),
                                      'tank_id': selectedTankId,
                                      'recorded_at':
                                          DateTime.now()
                                              .toUtc()
                                              .toIso8601String(),
                                      'device_uid': null,
                                    };

                                    for (final spec in visibleSpecs) {
                                      final raw =
                                          valueCtrls[spec.type]!.text.trim();
                                      if (raw.isEmpty) continue;
                                      final parsed = double.tryParse(raw);
                                      if (parsed == null) continue;
                                      payload[spec.readingField] =
                                          spec.isTemperature
                                              ? (AppSettings.useFahrenheit.value
                                                  ? parsed
                                                  : _cToF(parsed))
                                              : parsed;
                                    }

                                    final result = await OfflineStore.instance
                                        .saveReading(
                                          client: _supa,
                                          tankId: selectedTankId,
                                          payload: payload,
                                        );

                                    if (mounted) Navigator.pop(ctx);

                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result == OfflineSaveResult.synced
                                                ? 'Reading added'
                                                : 'Reading saved offline and will sync when you reconnect',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed: $e'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open manual entry: $e')),
      );
    }
  }

  Future<void> _pickFrom(
    ImageSource source,
    void Function(void Function()) setStateSheet,
  ) async {
    try {
      FocusScope.of(context).unfocus();

      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (xfile == null) return;

      final bytes = await xfile.readAsBytes();

      try {
        setStateSheet(() {
          _pendingImageBytes = bytes;
          _pendingImageName = xfile.name;
        });
      } catch (_) {
        _pendingImageBytes = bytes;
        _pendingImageName = xfile.name;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image error: $e')));
    }
  }

  Future<String> _uploadTankImage(Uint8List bytes) async {
    final uid = _supa.auth.currentUser!.id;
    final id = const Uuid().v4();
    final path = '$uid/tanks/$id.jpg';

    await _supa.storage
        .from('tank-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    final signed = await _supa.storage
        .from('tank-images')
        .createSignedUrl(path, 60 * 60 * 24 * 30);
    return signed;
  }

  static String _fmtDateShort(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 0,
      title: 'Dashboard',
      leadingSecondary: IconButton(
        tooltip: 'Search tanks',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.search, color: Colors.white, size: 22),
        onPressed: _openTankSearch,
      ),
      actions: [
        IconButton(
          tooltip: _hintForNextLayout(),
          icon: Icon(_iconForLayout(_layout), color: Colors.white),
          onPressed: _cycleLayout,
        ),
      ],
      aquaspecNamePrefix: 'AquaSpec',
      initialCredentials: const {'ssid': '', 'password': '', 'device_key': ''},
      overlay: Positioned(
        right: 16,
        bottom: 92,
        child: FloatingActionButton(
          backgroundColor: RotalaColors.teal,
          onPressed: _openAddTankSheet,
          child: const Icon(Icons.add, size: 28, color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: RefreshIndicator(
              color: Colors.tealAccent,
              backgroundColor: const Color(0xFF111827),
              onRefresh: _refreshHome,
              child: ValueListenableBuilder<bool>(
                valueListenable: AppSettings.useFahrenheit,
                builder: (context, useFahrenheit, _) {
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('tank_stream_$_refreshTick'),
                    stream: _tankStream,
                    builder: (context, snap) {
                      if (snap.hasData) {
                        final remote =
                            snap.data ?? const <Map<String, dynamic>>[];
                        _latestTanks = remote;
                        final uid = _supa.auth.currentUser?.id;
                        if (uid != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            OfflineStore.instance.cacheTanks(uid, remote);
                          });
                        }
                      }

                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData &&
                          _latestTanks.isEmpty) {
                        // needs to be scrollable for pull-to-refresh gesture
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 140),
                            Center(child: CircularProgressIndicator()),
                          ],
                        );
                      }

                      if (snap.hasError &&
                          (snap.data == null || (snap.data?.isEmpty ?? true)) &&
                          _latestTanks.isEmpty) {
                        final msg = snap.error.toString();
                        final isOffline =
                            msg.contains('SocketException') ||
                            msg.contains('Failed host lookup');

                        if (_retryingTanks) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 140),
                              const Center(child: CircularProgressIndicator()),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  isOffline ? 'Reconnecting…' : 'Trying again…',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          );
                        }

                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 90),
                            Icon(
                              isOffline ? Icons.wifi_off : Icons.error_outline,
                              color: Colors.white70,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isOffline
                                  ? 'Oops, looks like you are offline.'
                                  : 'Something went wrong while loading tanks.',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton.icon(
                                onPressed: _retryLoadTanks,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ),
                          ],
                        );
                      }

                      final all =
                          snap.hasData ? (snap.data ?? const []) : _latestTanks;
                      _latestTanks = all;

                      if (_retryingTanks && all.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _retryingTanks = false);
                        });
                      }

                      final tanks = all;

                      if (tanks.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 90),
                            Center(
                              child: TextButton.icon(
                                onPressed: _openAddTankSheet,
                                icon: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Add your first tank',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      if (_layout == LayoutMode.cards) {
                        // PageView isn't "pull-to-refresh"-friendly, so wrap in a scrollable parent.
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.62,
                              child: PageView.builder(
                                scrollDirection: Axis.vertical,
                                controller: PageController(
                                  viewportFraction: 1.0,
                                ),
                                physics:
                                    tanks.length == 1
                                        ? const NeverScrollableScrollPhysics()
                                        : const PageScrollPhysics(),
                                itemCount: tanks.length,
                                itemBuilder:
                                    (_, i) => Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == tanks.length - 1 ? 0 : 12,
                                      ),
                                      child: TankCard(
                                        row: tanks[i],
                                        onOpen: _openTankDetail,
                                        useFahrenheit: useFahrenheit,
                                      ),
                                    ),
                              ),
                            ),
                          ],
                        );
                      }

                      if (_layout == LayoutMode.list) {
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: tanks.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 12),
                          itemBuilder:
                              (_, i) => TankListTile(
                                row: tanks[i],
                                onOpen: _openTankDetail,
                                useFahrenheit: useFahrenheit,
                              ),
                        );
                      }

                      return GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 96),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                        itemCount: tanks.length,
                        itemBuilder:
                            (_, i) => TankGridCard(
                              row: tanks[i],
                              onOpen: _openTankDetail,
                              useFahrenheit: useFahrenheit,
                            ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalTask {
  final String id;
  final String title;
  final bool done;
  final DateTime? due;
  final String? tankId;

  const _GlobalTask({
    required this.id,
    required this.title,
    required this.done,
    this.due,
    this.tankId,
  });
}

enum _TaskFilter { all, open, completed }

class _TankSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  _TankSearchDelegate({required List<Map<String, dynamic>> tanks})
    : _tanks = List.unmodifiable(tanks);

  final List<Map<String, dynamic>> _tanks;

  Iterable<Map<String, dynamic>> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _tanks;

    return _tanks.where((row) {
      final name = (row['name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    });
  }

  String _subtitle(Map<String, dynamic> row) {
    final waterType = (row['water_type'] ?? 'freshwater').toString();
    final volumeGallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final label =
        waterType.isEmpty
            ? 'Freshwater'
            : '${waterType[0].toUpperCase()}${waterType.substring(1)}';
    return '$label • ${volumeGallons.toStringAsFixed(0)} gal';
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0b1220)),
      scaffoldBackgroundColor: const Color(0xFF0b1220),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear search',
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final results = _filtered().toList();
    if (results.isEmpty) {
      return const Center(
        child: Text('No tanks found.', style: TextStyle(color: Colors.white70)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = results[index];
        return ListTile(
          tileColor: const Color(0xFF1f2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF111827),
            child: Icon(Icons.water, color: Colors.white70),
          ),
          title: Text(
            (row['name'] ?? 'Tank').toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            _subtitle(row),
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white70),
          onTap: () => close(context, row),
        );
      },
    );
  }
}
