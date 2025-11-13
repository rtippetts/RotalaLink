import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/app_scaffold.dart';
import '../tank_detail_page.dart';
import 'quick_actions.dart';
import 'tank_views.dart';

// NEW
import 'package:shared_preferences/shared_preferences.dart';
import '../onboarding/walkthrough.dart';

// NEW imports you already had
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
    _tankStream = _supa.from('tanks').stream(primaryKey: ['id']).order('created_at');
    _searchCtrl.addListener(() => setState(() {}));

    // Show walkthrough once after first frame, if needed
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWalkthrough());
  }

  Future<void> _maybeShowWalkthrough() async {
    final seen = await WalkthroughScreen.hasSeen();
    if (seen) return;

    // Guard against showing on top of another route unexpectedly
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WalkthroughScreen(),
        fullscreenDialog: true,
      ),
    );

    // If user dismissed by system back, still mark as seen to avoid reappearing
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
                              final name = (row['name'] ?? '').toString().toLowerCase();
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
                            padding: EdgeInsets.only(bottom: i == tanks.length - 1 ? 0 : 12),
                            child: TankCard(
                              row: tanks[i],
                              onOpen: _openTankDetail,
                            ),
                          ),
                        );
                      } else if (_layout == LayoutMode.list) {
                        // compact list view
                        return ListView.separated(
                          itemCount: tanks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => TankListTile(
                            row: tanks[i],
                            onOpen: _openTankDetail,
                          ),
                        );
                      } else {
                        // grid2: two side by side, vertical scroll
                        return GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: tanks.length,
                          itemBuilder: (_, i) => TankGridCard(
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
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final items = (snap.data ?? const []).where((r) => r['user_id'] == uid).toList();
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
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                      itemBuilder: (_, i) {
                        final a = items[i];
                        final msg = a['message']?.toString() ?? 'Alert';
                        final created =
                            DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              const Icon(Icons.notification_important, color: Colors.amber),
                          title: Text(msg, style: const TextStyle(color: Colors.white)),
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
        return StatefulBuilder(builder: (ctx, setStateSheet) {
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
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),

                  // Water type
                  DropdownButtonFormField<String>(
                    value: waterType,
                    dropdownColor: const Color(0xFF0b1220),
                    items: const [
                      DropdownMenuItem(value: 'freshwater', child: Text('Freshwater')),
                      DropdownMenuItem(value: 'saltwater', child: Text('Saltwater')),
                      DropdownMenuItem(value: 'brackish', child: Text('Brackish')),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      const Icon(Icons.photo_camera_back, color: Colors.white70),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Photo (optional)', style: TextStyle(color: Colors.white70)),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickFrom(ImageSource.gallery, setStateSheet),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        onPressed: () => _pickFrom(ImageSource.camera, setStateSheet),
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
                              const SnackBar(content: Text('Saving...'), duration: Duration(seconds: 1)),
                            );

                            try {
                              final uid = _supa.auth.currentUser!.id;
                              String? imageUrl;
                              if (_pendingImageBytes != null) {
                                imageUrl = await _uploadTankImage(_pendingImageBytes!);
                              }

                              await _supa.from('tanks').insert({
                                'user_id': uid,
                                'name': nameCtrl.text.trim(),
                                'water_type': waterType,
                                'volume_gallons': double.parse(gallonsCtrl.text.trim()),
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
        });
      },
    );

    if (saved == true) {
      // StreamBuilder auto refresh
    }
  }

  // Manual entry bottom sheet
  Future<void> _openManualEntrySheet() async {
    try {
      final tanks = await _supa.from('tanks').select('id,name').order('created_at');
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
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'pH'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tdsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'TDS ppm'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Temperature °C'),
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
                                    'tds': double.tryParse(tdsCtrl.text.trim()),
                                  if (tempCtrl.text.trim().isNotEmpty)
                                    'temperature_c': double.tryParse(tempCtrl.text.trim()),
                                });
                                if (mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Reading added')),
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
              );
            }),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open manual entry: $e')));
    }
  }

  // Image helpers
  Future<void> _pickFrom(ImageSource source, void Function(void Function()) setStateSheet) async {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image error: $e')));
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

    final signed =
        await _supa.storage.from('tank-images').createSignedUrl(path, 60 * 60 * 24 * 30);
    return signed;
  }

  // Helpers
  static String _fmtDateShort(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}"
        "/${d.month.toString().padLeft(2, '0')}"
        "/${d.day.toString().padLeft(2, '0')}";
  }
}
