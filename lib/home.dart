import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_scaffold.dart';
import '../tank_detail_page.dart';
import 'quick_actions.dart';
import 'tank_views.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../onboarding/walkthrough.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'theme/rotala_brand.dart';
import 'app_settings.dart';



final _supa = Supabase.instance.client;

// Helper to derive a friendly first name from user metadata or email
String _firstNameFromUser(User? user) {
  if (user == null) return '';

  final md = user.userMetadata ?? {};

  final fn = (md['first_name'] ?? '').toString().trim();
  if (fn.isNotEmpty && fn != '-') return fn;

  final disp = (md['display_name'] ?? '').toString().trim();
  if (disp.isNotEmpty && disp != '-') {
    if (disp.contains(',')) {
      // Format like: Last, First Middle
      final parts = disp.split(',');
      if (parts.length > 1) {
        final right = parts[1].trim();
        if (right.isNotEmpty) {
          return right.split(RegExp(r'\s+')).first;
        }
      }
    } else {
      // Format like: First Last
      final tokens = disp.split(RegExp(r'\s+'));
      if (tokens.isNotEmpty) return tokens.first;
    }
  }

  final email = user.email ?? '';
  if (email.contains('@')) return email.split('@').first;
  return '';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum LayoutMode { grid2, list, cards }

class _HomePageState extends State<HomePage> {
  late final Stream<List<Map<String, dynamic>>> _tankStream;

  // picker plus in sheet image state
  final _picker = ImagePicker();
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  // UI state
  final TextEditingController _searchCtrl = TextEditingController();
  LayoutMode _layout = LayoutMode.grid2; // default to two column view

  // global tasks state
  final List<_GlobalTask> _globalTasks = [];
  bool _loadingGlobalTasks = false;

  @override
  void initState() {
    super.initState();
    _tankStream =
        _supa.from('tanks').stream(primaryKey: ['id']).order('created_at');
    _searchCtrl.addListener(() => setState(() {}));

    // Load persisted unit settings (F vs C, gallons vs liters)
    AppSettings.load();

    // Show walkthrough once after first frame, if needed
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowWalkthrough());
  }


  Future<void> _openAddTaskSheet() async {
    final uid = _supa.auth.currentUser?.id;
    if (uid == null) return;

    final tanks =
        await _supa.from('tanks').select('id,name').order('created_at');

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

                  // Title
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Task title',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Tank selector (nullable)
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
                        )
                    ],
                    onChanged: (v) => setSheet(() => selectedTankId = v),
                    decoration: const InputDecoration(
                      labelText: 'Attach to tank',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Choose due date
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
                      )
                    ],
                  ),

                  const SizedBox(height: 16),

                  FilledButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) return;

                      await _supa.from('tank_tasks').insert({
                        'user_id': uid,
                        'title': titleCtrl.text.trim(),
                        'tank_id': selectedTankId, // nullable
                        'done': false,
                        if (dueDate != null)
                          'due_at': dueDate!.toIso8601String(),
                      });

                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  )
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _maybeShowWalkthrough() async {
  final seen = await WalkthroughScreen.hasSeen();
  if (seen || !mounted) return;

  // First time for this user, show the walkthrough
  await WalkthroughScreen.show(context);

  // If user exited with system back and markSeen was not called,
  // force mark it so it does not auto show again
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(kWalkthroughSeenKey) ?? false)) {
    await WalkthroughScreen.markSeen();
  }
}


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // format with date and time for global tasks
  String _timeExactGlobal(DateTime t) {
    final date =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }

  // load all tasks for the signed in user
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

      final list = (rows as List)
          .map(
            (r) => _GlobalTask(
              id: r['id'] as String,
              title: (r['title'] ?? '') as String,
              done: r['done'] == true,
              due: r['due_at'] == null
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to manage tasks')),
      );
      return;
    }

    final title = TextEditingController(text: existing?.title ?? '');
    DateTime? due = existing?.due;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
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
                  leading:
                      const Icon(Icons.edit_calendar, color: Colors.white70),
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
                      () => due = DateTime(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty')),
      );
      return;
    }

    if (existing == null) {
      // New task defaults to a general task
      await _supa.from('tank_tasks').insert({
        'user_id': uid,
        'tank_id': null,
        'title': title.text.trim(),
        'done': false,
        'due_at': due?.toUtc().toIso8601String(),
      });
    } else {
      await _supa.from('tank_tasks').update({
        'title': title.text.trim(),
        'due_at': due?.toUtc().toIso8601String(),
      }).eq('id', existing.id);
    }

    await _loadGlobalTasks();
  }

  Future<void> _deleteGlobalTask(_GlobalTask t) async {
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

    await _supa.from('tank_tasks').delete().eq('id', t.id);
    await _loadGlobalTasks();
  }

  @override
  Widget build(BuildContext context) {
    // Friendly title with first name if present
    final user = _supa.auth.currentUser;
    final firstName = _firstNameFromUser(user);
    final title = firstName.isEmpty ? 'Welcome' : 'Welcome back, $firstName';

    return AppScaffold(
      currentIndex: 0,
      title: title,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Actions card with greeting
                QuickActionsCard(
                  tankStream: _tankStream,
                  onOpenTasks: _openTasksSheet,
                  onAddReading: _openManualEntrySheet,
                  greetingName: firstName,
                ),
                const SizedBox(height: 16),

                // top actions row
                Row(
                  children: [
                    Expanded(child: _buildSearchField()),
                    const SizedBox(width: 12),
                    _layoutToggle(),
                  ],
                ),
                const SizedBox(height: 16),

                                // Rebuild tank views when the temperature unit changes
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.useFahrenheit,
                    builder: (context, useFahrenheit, _) {
                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _tankStream,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Error loading tanks: ${snap.error}',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            );
                          }

                          final all = snap.data ?? const [];
                          final q = _searchCtrl.text.trim().toLowerCase();
                          final tanks = q.isEmpty
                              ? all
                              : all.where((row) {
                                  final name = (row['name'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  return name.contains(q);
                                }).toList();

                          if (tanks.isEmpty) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: _openAddTankSheet,
                                icon: const Icon(Icons.add, color: Colors.white),
                                label: const Text(
                                  'Add your first tank',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          }

                          if (_layout == LayoutMode.cards) {
                            // Full height cards
                            return PageView.builder(
                              scrollDirection: Axis.vertical,
                              controller: PageController(viewportFraction: 1.0),
                              physics: tanks.length == 1
                                  ? const NeverScrollableScrollPhysics()
                                  : const PageScrollPhysics(),
                              itemCount: tanks.length,
                              itemBuilder: (_, i) => Padding(
                                padding: EdgeInsets.only(
                                  bottom: i == tanks.length - 1 ? 0 : 12,
                                ),
                                child: TankCard(
                                  row: tanks[i],
                                  onOpen: _openTankDetail,
                                  useFahrenheit: useFahrenheit,
                                ),
                              ),
                            );
                          } else if (_layout == LayoutMode.list) {
                            // compact list view
                            return ListView.separated(
                              itemCount: tanks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => TankListTile(
                                row: tanks[i],
                                onOpen: _openTankDetail,
                                useFahrenheit: useFahrenheit,
                              ),
                            );
                          } else {
                            // grid2: two side by side, vertical scroll
                            return GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: tanks.length,
                              itemBuilder: (_, i) => TankGridCard(
                                row: tanks[i],
                                onOpen: _openTankDetail,
                                useFahrenheit: useFahrenheit,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),


                const SizedBox(height: 30),
              ],
            ),
          ),

          Positioned(
            right: 16,
            bottom: 16 + 56,
            child: FloatingActionButton.extended(
              backgroundColor: RotalaColors.teal,
              onPressed: _openAddTankSheet,
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add,
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Icon(
                    MdiIcons.fishbowlOutline,
                    size: 30,
                    color: Colors.white,
                  ),
                ],
              ),
              label: const SizedBox.shrink(),
              extendedPadding:
                  const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search tanks',
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon:
            const Icon(Icons.search, color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF0b1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
    );
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

  Widget _layoutToggle() {
    return Tooltip(
      message: _hintForNextLayout(),
      child: InkWell(
        onTap: () {
          setState(() {
            // grid2 -> list -> cards -> grid2
            if (_layout == LayoutMode.grid2) {
              _layout = LayoutMode.list;
            } else if (_layout == LayoutMode.list) {
              _layout = LayoutMode.cards;
            } else {
              _layout = LayoutMode.grid2;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0b1220),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _iconForLayout(_layout),
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _openTankDetail(Tank tank) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TankDetailPage(tank: tank),
      ),
    );
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
                  prefixIcon: Icon(
                    Icons.smart_toy,
                    color: Colors.white70,
                  ),
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

  // tasks bottom sheet with search and filter
  // tasks bottom sheet with search, status filter, and tank filter
// tasks bottom sheet with status filter and tank filter (no search bar)
// tasks bottom sheet with status filter and tank filter (no search bar)
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

  // load tasks once before opening to avoid setState during build
  await _loadGlobalTasks();

  // load tanks for filter dropdown
  final List<dynamic> tanks = await _supa
      .from('tanks')
      .select('id,name')
      .order('created_at');

  // local state for this sheet
  _TaskFilter filter = _TaskFilter.open;
  String? selectedTankId; // null means "All tanks"

  // track tasks that are in the middle of a toggle so the user
  // can see the checkbox animation before the row moves
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

              // apply status and tank filter
              List<_GlobalTask> visible = List.of(_globalTasks);

              if (filter == _TaskFilter.open) {
                visible = visible.where((t) => !t.done).toList();
              } else if (filter == _TaskFilter.completed) {
                visible = visible.where((t) => t.done).toList();
              }

              if (selectedTankId != null) {
                visible = visible.where((t) => t.tankId == selectedTankId).toList();
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

                      // while a task is in pendingToggles, show the checkbox in the
                      // opposite state of its stored value so the animation is visible
                      final bool checkboxValue = pendingToggles.contains(t.id)
                          ? !t.done
                          : t.done;

                      return Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CheckboxListTile(
                          value: checkboxValue,
                          onChanged: (v) async {
                            if (v == null) return;

                            // immediately show the visual toggle
                            setSheet(() {
                              pendingToggles.add(t.id);
                            });

                            try {
                              // brief pause so the user can see the check
                              await Future.delayed(
                                const Duration(milliseconds: 220),
                              );

                              // commit to Supabase
                              await _supa
                                  .from('tank_tasks')
                                  .update({'done': v})
                                  .eq('id', t.id);

                              pendingToggles.remove(t.id);

                              await refresh();

                              // show confirmation with Undo
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    v ? 'Task marked complete' : 'Task reopened',
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
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Could not undo: $e'),
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
                          subtitle: t.due == null
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
                            itemBuilder: (_) => const [
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
                  // header row
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

                  // tank filter dropdown
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
                          child: Text(
                            t['name']?.toString() ?? 'Tank',
                          ),
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

                  // status filter chips
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        labelStyle: TextStyle(
                          color: filter == _TaskFilter.all
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
                          color: filter == _TaskFilter.open
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
                          color: filter == _TaskFilter.completed
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




  // bottom sheet to add a tank
Future<void> _openAddTankSheet() async {
  _pendingImageBytes = null;
  _pendingImageName = null;

  final formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final volumeCtrl = TextEditingController();
  String waterType = 'freshwater';

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
                  final volumeLabel =
                      useGallons ? 'Volume (gallons)' : 'Volume (liters)';
                  final volumeHelper = useGallons
                      ? 'Enter tank size in gallons'
                      : 'Enter tank size in liters';

                  return Column(
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
                      const SizedBox(height: 12),

                      // Name
                      TextFormField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: Colors.white70),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),

                      // Water type
                      DropdownButtonFormField<String>(
                        value: waterType,
                        dropdownColor: const Color(0xFF1f2937),
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
                        decoration: const InputDecoration(
                          labelText: 'Water type',
                          labelStyle: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Volume (reactive to gallons vs liters)
                      TextFormField(
                        controller: volumeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: volumeLabel,
                          labelStyle: const TextStyle(color: Colors.white70),
                          helperText: volumeHelper,
                          helperStyle: const TextStyle(color: Colors.white38),
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) {
                            return 'Enter a number greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Photo picker
                      Row(
                        children: [
                          const Icon(
                            Icons.photo_camera_back,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Photo (optional)',
                              style: TextStyle(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              FocusScope.of(ctx).unfocus();
                              await _pickFrom(ImageSource.gallery, setStateSheet);
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
),

                          const SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: () async {
                              // Use the sheet context (ctx) for focus so the sheet does not get weird
                              FocusScope.of(ctx).unfocus();
                              await _pickFrom(ImageSource.camera, setStateSheet);
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
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) {
                                  return;
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Saving...'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );

                                try {
                                  final uid = _supa.auth.currentUser!.id;
                                  String? imageUrl;
                                  if (_pendingImageBytes != null) {
                                    imageUrl =
                                        await _uploadTankImage(_pendingImageBytes!);
                                  }

                                  // Convert to liters and gallons with liters as source of truth
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

                                  await _supa.from('tanks').insert({
                                    'user_id': uid,
                                    'name': nameCtrl.text.trim(),
                                    'water_type': waterType,
                                    'volume_liters': liters,
                                    'volume_gallons': gallons,
                                    if (imageUrl != null) 'image_url': imageUrl,
                                  });

                                  if (mounted) {
                                    Navigator.pop(ctx, true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Tank added'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
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
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );

  if (saved == true) {
    // StreamBuilder auto refresh
  }
}


  // Manual entry bottom sheet
  Future<void> _openManualEntrySheet() async {
    try {
      final tanks = await _supa
          .from('tanks')
          .select('id,name')
          .order('created_at');
      if (!mounted) return;

      String? tankId =
          tanks.isNotEmpty ? tanks.first['id'] as String : null;
      final phCtrl = TextEditingController();
      final tdsCtrl = TextEditingController();
      final tempCtrl = TextEditingController();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1f2937),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16)),
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
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
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
                        for (final t in tanks)
                          DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(
                              t['name']?.toString() ??
                                  'Tank',
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setSheet(() => tankId = v),
                      decoration: const InputDecoration(
                        labelText: 'Tank',
                        labelStyle:
                            TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'pH',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tdsCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'TDS ppm',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tempCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temperature °C',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: tankId == null
                            ? null
                            : () async {
                                try {
                                  await _supa
                                      .from('sensor_readings')
                                      .insert({
                                    'tank_id': tankId,
                                    if (phCtrl.text
                                        .trim()
                                        .isNotEmpty)
                                      'ph': double.tryParse(
                                        phCtrl.text
                                            .trim(),
                                      ),
                                    if (tdsCtrl.text
                                        .trim()
                                        .isNotEmpty)
                                      'tds':
                                          double.tryParse(
                                        tdsCtrl.text
                                            .trim(),
                                      ),
                                    if (tempCtrl.text
                                        .trim()
                                        .isNotEmpty)
                                      'temperature_c':
                                          double.tryParse(
                                        tempCtrl.text
                                            .trim(),
                                      ),
                                  });
                                  if (mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Reading added',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed: $e',
                                        ),
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
                );
              },
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open manual entry: $e',
          ),
        ),
      );
    }
  }

  // Image helpers
  Future<void> _pickFrom(
  ImageSource source,
  void Function(void Function()) setStateSheet,
) async {
  try {
    // This closes any open keyboard before opening camera/gallery,
    // which helps keep the bottom sheet stable on iOS.
    FocusScope.of(context).unfocus();

    final xfile = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (xfile == null) {
      // User cancelled
      return;
    }

    final bytes = await xfile.readAsBytes();

    // At this point the bottom sheet *should* still be in the tree.
    // If for some reason it was dismissed, setStateSheet would throw,
    // so we wrap it defensively.
    try {
      setStateSheet(() {
        _pendingImageBytes = bytes;
        _pendingImageName = xfile.name;
      });
    } catch (_) {
      // Sheet was closed; just keep the bytes so next time you open
      // the sheet we can still use them if you want.
      _pendingImageBytes = bytes;
      _pendingImageName = xfile.name;
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Image error: $e'),
      ),
    );
  }
}


  /// Uploads to 'tank images' bucket at '{uid}/tanks/{uuid}.jpg'
  /// Returns a signed URL for display
  Future<String> _uploadTankImage(Uint8List bytes) async {
    final uid = _supa.auth.currentUser!.id;
    final id = const Uuid().v4();
    final path = '$uid/tanks/$id.jpg';

    await _supa.storage.from('tank-images').uploadBinary(
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

  // Export CSV placeholder
  void _exportCsvComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('CSV export is coming in a future update'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Helpers
  static String _fmtDateShort(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}"
        "/${d.month.toString().padLeft(2, '0')}"
        "/${d.day.toString().padLeft(2, '0')}";
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
