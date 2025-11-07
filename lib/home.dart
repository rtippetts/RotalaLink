// lib/home.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/app_scaffold.dart';
import 'tank_detail_page.dart';

// NEW imports
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

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

  // picker + in sheet image state
  final _picker = ImagePicker();
  Uint8List? _pendingImageBytes;
  String? _pendingImageName;

  // UI state
  final TextEditingController _searchCtrl = TextEditingController();
  LayoutMode _layout = LayoutMode.grid2; // default to two column view

  @override
  void initState() {
    super.initState();
    _tankStream =
        _supa.from('tanks').stream(primaryKey: ['id']).order('created_at');
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                _QuickActionsCard(
                  tankStream: _tankStream,
                  onOpenAlerts: _openAlertsSheet,
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
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _tankStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
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
                              final name =
                                  (row['name'] ?? '').toString().toLowerCase();
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
                        // Full height cards. No half-peek.
                        return PageView.builder(
                          scrollDirection: Axis.vertical,
                          controller: PageController(viewportFraction: 1.0),
                          physics: tanks.length == 1
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemCount: tanks.length,
                          itemBuilder: (_, i) => Padding(
                            padding: EdgeInsets.only(
                                bottom: i == tanks.length - 1 ? 0 : 12),
                            child: _TankCard(
                              row: tanks[i],
                              onOpen: _openTankDetail,
                            ),
                          ),
                        );
                      } else if (_layout == LayoutMode.list) {
                        // compact list view
                        return ListView.separated(
                          itemCount: tanks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _TankListTile(
                            row: tanks[i],
                            onOpen: _openTankDetail,
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
                          itemBuilder: (_, i) => _TankGridCard(
                            row: tanks[i],
                            onOpen: _openTankDetail,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),

          // Bottom right: clearer New tank FAB
          Positioned(
            right: 16,
            bottom: 16 + 56,
            child: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF06b6d4),
              onPressed: _openAddTankSheet,
              icon: const Icon(Icons.water_drop),
              label: const Text('New tank'),
            ),
          ),

          // Bottom left: chatbot FAB
          Positioned(
            left: 16,
            bottom: 16 + 56,
            child: FloatingActionButton(
              heroTag: 'assistantFab',
              onPressed: _openAssistantSheet,
              backgroundColor: const Color(0xFF1f2937),
              child: const Icon(Icons.smart_toy, color: Colors.white),
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
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF0b1220),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
      MaterialPageRoute(builder: (_) => TankDetailPage(tank: tank)),
    );
  }

  // Assistant sheet placeholder
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
              const Text('Assistant',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
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

  // Alerts bottom sheet with uid null guard
  Future<void> _openAlertsSheet() async {
    final uid = _supa.auth.currentUser?.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        if (uid == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to view alerts',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        // No .eq on stream to avoid compile error. Filter in the builder.
        final stream = _supa
            .from('alerts')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Alerts',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = (snap.data ?? const [])
                        .where((r) => r['user_id'] == uid)
                        .toList();
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No alerts',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white12),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        final msg = a['message']?.toString() ?? 'Alert';
                        final created = DateTime.tryParse(
                                a['created_at']?.toString() ?? '') ??
                            DateTime.now();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.notification_important,
                              color: Colors.amber),
                          title: Text(msg,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            _fmtDateShort(created),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
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
    final gallonsCtrl = TextEditingController();
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Tank',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
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
                      dropdownColor: const Color(0xFF0b1220),
                      items: const [
                        DropdownMenuItem(
                            value: 'freshwater', child: Text('Freshwater')),
                        DropdownMenuItem(
                            value: 'saltwater', child: Text('Saltwater')),
                        DropdownMenuItem(
                            value: 'brackish', child: Text('Brackish')),
                      ],
                      onChanged: (v) => waterType = v ?? 'freshwater',
                      decoration: const InputDecoration(
                        labelText: 'Water type',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Gallons
                    TextFormField(
                      controller: gallonsCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Volume (gallons)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'Enter a number > 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Photo picker
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_back,
                            color: Colors.white70),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Photo (optional)',
                              style: TextStyle(color: Colors.white70)),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _pickFrom(ImageSource.gallery, setStateSheet),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: () =>
                              _pickFrom(ImageSource.camera, setStateSheet),
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
                              if (!formKey.currentState!.validate()) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Saving...'),
                                    duration: Duration(seconds: 1)),
                              );

                              try {
                                final uid = _supa.auth.currentUser!.id;

                                String? imageUrl;
                                if (_pendingImageBytes != null) {
                                  imageUrl = await _uploadTankImage(
                                      _pendingImageBytes!);
                                }

                                await _supa.from('tanks').insert({
                                  'user_id': uid,
                                  'name': nameCtrl.text.trim(),
                                  'water_type': waterType,
                                  'volume_gallons':
                                      double.parse(gallonsCtrl.text.trim()),
                                  if (imageUrl != null) 'image_url': imageUrl,
                                });

                                if (mounted) {
                                  Navigator.pop(ctx, true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Tank added')),
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
      final tanks =
          await _supa.from('tanks').select('id,name').order('created_at');
      if (!mounted) return;

      String? tankId = tanks.isNotEmpty ? tanks.first['id'] as String : null;
      final phCtrl = TextEditingController();
      final tdsCtrl = TextEditingController();
      final tempCtrl = TextEditingController();

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
            child: StatefulBuilder(builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add reading',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: tankId,
                    dropdownColor: const Color(0xFF0b1220),
                    items: [
                      for (final t in tanks)
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
                  TextField(
                    controller: phCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'pH'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tdsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'TDS ppm'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tempCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Temperature °C'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: tankId == null
                          ? null
                          : () async {
                              try {
                                await _supa.from('measurements').insert({
                                  'tank_id': tankId,
                                  if (phCtrl.text.trim().isNotEmpty)
                                    'ph': double.tryParse(phCtrl.text.trim()),
                                  if (tdsCtrl.text.trim().isNotEmpty)
                                    'tds':
                                        double.tryParse(tdsCtrl.text.trim()),
                                  if (tempCtrl.text.trim().isNotEmpty)
                                    'temperature_c':
                                        double.tryParse(tempCtrl.text.trim()),
                                });
                                if (mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Reading added')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('Failed: $e'),
                                        backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              );
            }),
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

  // Image helpers
  Future<void> _pickFrom(
      ImageSource source, void Function(void Function()) setStateSheet) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (xfile == null) return;
      _pendingImageBytes = await xfile.readAsBytes();
      _pendingImageName = xfile.name;
      setStateSheet(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image error: $e')),
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

  // Helpers
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

  Widget _placeholderImage() => Container(
        height: 160,
        width: double.infinity,
        color: const Color(0xFF0b1220),
        child: const Center(
          child: Icon(Icons.water, color: Colors.white54, size: 28),
        ),
      );

  static String _fmtDateShort(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}"
        "/${d.month.toString().padLeft(2, '0')}"
        "/${d.day.toString().padLeft(2, '0')}";
  }
}

// Quick Actions card widget with greeting
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.tankStream,
    required this.onOpenAlerts,
    required this.onAddReading,
    required this.greetingName,
  });

  final Stream<List<Map<String, dynamic>>> tankStream;
  final VoidCallback onOpenAlerts;
  final VoidCallback onAddReading;
  final String greetingName;

  Future<_DeviceStatus> _fetchDeviceStatus() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return const _DeviceStatus.unknown();
      final rows = await Supabase.instance.client
          .from('devices')
          .select('connected,last_seen')
          .eq('user_id', uid)
          .order('last_seen', ascending: false)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        final connected = (r['connected'] == true);
        final lastSeenStr = r['last_seen']?.toString();
        final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
        final online = connected ||
            (lastSeen != null &&
                DateTime.now().difference(lastSeen).inMinutes <= 5);
        return _DeviceStatus(online: online, lastSeen: lastSeen);
      }
      return const _DeviceStatus.unknown();
    } catch (_) {
      return const _DeviceStatus.unknown();
    }
  }

  int _countDueToday(List<Map<String, dynamic>> tanks) {
    int due = 0;
    for (final t in tanks) {
      final wt = (t['water_type'] ?? 'freshwater').toString();
      final cadence = wt == 'saltwater'
          ? const Duration(days: 3)
          : wt == 'brackish'
              ? const Duration(days: 5)
              : const Duration(days: 7);
      final lastStr = t['last_measurement_at']?.toString();
      DateTime last = DateTime.now().subtract(const Duration(days: 30));
      if (lastStr != null) {
        final parsed = DateTime.tryParse(lastStr);
        if (parsed != null) last = parsed;
      }
      final next = last.add(cadence);
      final now = DateTime.now();
      final sameDay = next.year == now.year &&
          next.month == now.month &&
          next.day == now.day;
      final overdue = next.isBefore(now) && !sameDay;
      if (sameDay || overdue) due += 1;
    }
    return due;
  }

  @override
  Widget build(BuildContext context) {
    final name = greetingName.isEmpty ? 'there' : greetingName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF122033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting row
          Row(
            children: [
              const Icon(Icons.handshake_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Welcome back, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tasks summary
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: tankStream,
            builder: (context, snap) {
              final tanks = snap.data ?? const [];
              final due = _countDueToday(tanks);
              return Row(
                children: [
                  const Icon(Icons.waves_outlined,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      due == 0
                          ? 'All tanks look good today'
                          : '$due tank${due == 1 ? '' : 's'} need attention today',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // Actions row
          Row(
            children: [
              // Alerts
              Expanded(
                child: _ActionPill(
                  icon: Icons.notifications,
                  labelBuilder: (ctx) => _AlertsCountBadge(onTap: onOpenAlerts),
                  onTap: onOpenAlerts,
                ),
              ),
              const SizedBox(width: 8),

              // Device status
              Expanded(
                child: FutureBuilder<_DeviceStatus>(
                  future: _fetchDeviceStatus(),
                  builder: (context, snap) {
                    final st = snap.data ?? const _DeviceStatus.unknown();
                    final online = st.online;
                    final icon =
                        online ? Icons.check_circle : Icons.portable_wifi_off;
                    final color =
                        online ? Colors.greenAccent : Colors.orangeAccent;
                    final text = online ? 'Device online' : 'Device offline';
                    return _ActionPill(
                      icon: icon,
                      iconColor: color,
                      label: text,
                      onTap: () {},
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Add reading
              Expanded(
                child: _ActionPill(
                  icon: Icons.add_chart,
                  label: 'Add reading',
                  onTap: onAddReading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    this.iconColor,
    this.label,
    this.labelBuilder,
    required this.onTap,
  }) : assert(label != null || labelBuilder != null);

  final IconData icon;
  final Color? iconColor;
  final String? label;
  final Widget Function(BuildContext)? labelBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0b1220),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor ?? Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: labelBuilder != null
                  ? labelBuilder!(context)
                  : Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertsCountBadge extends StatelessWidget {
  const _AlertsCountBadge({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return const Text('Alerts', style: TextStyle(color: Colors.white));
    }

    final stream = Supabase.instance.client
        .from('alerts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snap) {
        final items = (snap.data ?? const []);
        final mine = items.where((r) => r['user_id'] == uid);
        final count = mine.where((r) => r['acknowledged'] == false).length;

        if (count <= 0) {
          return const Text('Alerts', style: TextStyle(color: Colors.white));
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Alerts', style: TextStyle(color: Colors.white)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeviceStatus {
  final bool online;
  final DateTime? lastSeen;
  const _DeviceStatus({required this.online, this.lastSeen});
  const _DeviceStatus.unknown()
      : online = false,
        lastSeen = null;
}

// Big card for PageView
class _TankCard extends StatelessWidget {
  const _TankCard({required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
    );

    return GestureDetector(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholderImage(),
                    )
                  : _placeholderImage(),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            // latest parameters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _LatestParams(tankId: id),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  Widget _placeholderImage() => Container(
        height: 200,
        width: double.infinity,
        color: const Color(0xFF0b1220),
        child: const Center(
          child: Icon(Icons.water, color: Colors.white54, size: 28),
        ),
      );
}

// Compact tile for list mode
class _TankListTile extends StatelessWidget {
  const _TankListTile({required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
    );

    return InkWell(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                ? Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ph(),
                  )
                : _ph(),
          ),
          title: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              _LatestParams(tankId: id, compact: true),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white70),
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  static Widget _ph() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFF0b1220),
        child: const Icon(Icons.water, color: Colors.white54),
      );
}

// Grid card for grid2 mode
class _TankGridCard extends StatelessWidget {
  const _TankGridCard({required this.row, required this.onOpen});

  final Map<String, dynamic> row;
  final void Function(Tank) onOpen;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] ?? 'Tank') as String;
    final waterType = (row['water_type'] ?? 'freshwater') as String;
    final gallons = (row['volume_gallons'] as num?)?.toDouble() ?? 0;
    final liters = gallons * 3.785411784;
    final imageUrl = row['image_url'] as String?;
    final tank = Tank(
      id: id,
      name: name,
      volumeLiters: liters,
      inhabitants: _labelForWaterType(waterType),
    );

    return InkWell(
      onTap: () => onOpen(tank),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1f2937),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // taller image to keep aspect pleasant in grid
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: (imageUrl != null && imageUrl.trim().isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _ph(),
                    )
                  : _ph(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _LatestParams(tankId: id, compact: true),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static String _labelForWaterType(String v) {
    switch (v) {
      case 'saltwater':
        return 'Saltwater';
      case 'brackish':
        return 'Brackish';
      default:
        return 'Freshwater';
    }
  }

  static Widget _ph() => Container(
        height: 120,
        width: double.infinity,
        color: const Color(0xFF0b1220),
        child: const Center(
          child: Icon(Icons.water, color: Colors.white54, size: 28),
        ),
      );
}

// Latest parameters widget with icons for Temp, pH, TDS
class _LatestParams extends StatelessWidget {
  const _LatestParams({required this.tankId, this.compact = false});

  final String tankId;
  final bool compact;

  Future<Map<String, dynamic>?> _fetchLatest() async {
    final row = await _supa
        .from('measurements')
        .select('created_at, ph, tds, temperature, temperature_c')
        .eq('tank_id', tankId)
        .order('created_at', ascending: false)
        .maybeSingle();

    return row;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchLatest(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text(
            'Loading latest test...',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          );
        }
        final m = snap.data;
        if (m == null) {
          return const Text(
            'No tests yet',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          );
        }

        // Read values
        final double? temp =
            _asDouble(m['temperature']) ?? _asDouble(m['temperature_c']);
        final double? ph = _asDouble(m['ph']);
        final double? tds = _asDouble(m['tds']);
        final dt = DateTime.tryParse(m['created_at']?.toString() ?? '');
        final when = dt == null
            ? ''
            : "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}";

        // If compact, render a tight row
        if (compact) {
          return Row(
            children: [
              _miniIconValue(
                icon: Icons.thermostat,
                text: temp == null ? '-' : '${temp.toStringAsFixed(1)}°C',
              ),
              const SizedBox(width: 10),
              _miniIconValue(
                icon: Icons.science,
                text: ph == null ? '-' : ph.toStringAsFixed(2),
              ),
              const SizedBox(width: 10),
              _miniIconValue(
                icon: Icons.bubble_chart,
                text: tds == null ? '-' : '${tds.toStringAsFixed(0)} ppm',
              ),
              if (when.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    when,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ],
          );
        }

        // Full layout with heading
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Latest test',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _iconTile(
                    icon: Icons.thermostat,
                    label: 'Temp',
                    value: temp == null ? '-' : '${temp.toStringAsFixed(1)}°C',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.science,
                    label: 'pH',
                    value: ph == null ? '-' : ph.toStringAsFixed(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _iconTile(
                    icon: Icons.bubble_chart,
                    label: 'TDS',
                    value: tds == null ? '-' : '${tds.toStringAsFixed(0)} ppm',
                  ),
                ),
              ],
            ),
            if (when.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(when,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ],
        );
      },
    );
  }

  // Helpers
  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _iconTile(
      {required IconData icon,
      required String label,
      required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0b1220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconValue({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
