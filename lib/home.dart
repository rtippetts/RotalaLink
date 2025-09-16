// lib/home.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/app_scaffold.dart';
import 'tank_detail_page.dart';

// convenient alias
final _supa = Supabase.instance.client;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Stream<List<Map<String, dynamic>>> _tankStream;

  @override
  void initState() {
    super.initState();
    // RLS should filter to the signed-in user automatically
    _tankStream = _supa
        .from('tanks')
        .stream(primaryKey: ['id'])
        .order('created_at'); // if you added created_at
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 0,
      title: "Welcome, user",
      // We use a Stack so we can float a FAB above the body even if AppScaffold
      // doesn't expose floatingActionButton.
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== Dashboard card =====
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1f2937),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Dashboard",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text("Alerts",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("• pH level too low in Tank 2",
                          style: TextStyle(color: Colors.white)),
                      Text("• Temperature high in Tank 4",
                          style: TextStyle(color: Colors.white)),
                      SizedBox(height: 16),
                      Text("Tasks",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("• Clean filter in Tank 1",
                          style: TextStyle(color: Colors.white)),
                      Text("• Change water in Tank 3",
                          style: TextStyle(color: Colors.white)),
                      SizedBox(height: 16),
                      Text("Connection Status",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text("• All devices connected",
                          style: TextStyle(color: Colors.greenAccent)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ===== Tanks header =====
                const Text(
                  "Your Tanks",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Real tanks carousel =====
                SizedBox(
                  height: 240,
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _tankStream,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Error loading tanks: ${snap.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        );
                      }
                      final tanks = snap.data ?? const [];

                      if (tanks.isEmpty) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: _openAddTankSheet,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add your first tank",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tanks.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final row = tanks[index];
                          final id = row['id'] as String;
                          final name = (row['name'] ?? 'Tank') as String;
                          final waterType =
                          (row['water_type'] ?? 'freshwater') as String;
                          final gallons =
                              (row['volume_gallons'] as num?)?.toDouble() ?? 0;
                          final liters = gallons * 3.785411784;
                          final imageUrl = row['image_url'] as String?;
                          final tank = Tank(
                            id: id,
                            name: name,
                            volumeLiters: liters,
                            inhabitants:
                            _labelForWaterType(waterType), // simple mapping
                          );

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TankDetailPage(tank: tank),
                                ),
                              );
                            },
                            child: Container(
                              width: 200,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1f2937),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16)),
                                    child: (imageUrl != null &&
                                        imageUrl.trim().isNotEmpty)
                                        ? Image.network(
                                      imageUrl,
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _placeholderImage(),
                                    )
                                        : _placeholderImage(),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Text(
                                      '${_labelForWaterType(waterType)} • ${gallons.toStringAsFixed(0)} gal',
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 90), // leave room so FAB doesn't cover
              ],
            ),
          ),

          // ===== FAB (bottom-right, above bottom bar) =====
          Positioned(
            right: 16,
            bottom: 16 + 56, // 56 ≈ typical bottom bar height
            child: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF06b6d4),
              onPressed: _openAddTankSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- bottom sheet to add a tank ----------
  Future<void> _openAddTankSheet() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final gallonsCtrl = TextEditingController();
    String waterType = 'freshwater';
    final imageCtrl = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
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
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Tank',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
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
                DropdownButtonFormField<String>(
                  value: waterType,
                  dropdownColor: const Color(0xFF0b1220),
                  items: const [
                    DropdownMenuItem(
                        value: 'freshwater', child: Text('Freshwater')),
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
                TextFormField(
                  controller: imageCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                    labelStyle: TextStyle(color: Colors.white70),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          try {
                            final uid = _supa.auth.currentUser!.id;
                            await _supa.from('tanks').insert({
                              'user_id': uid,
                              'name': nameCtrl.text.trim(),
                              'water_type': waterType,
                              'volume_gallons':
                              double.parse(gallonsCtrl.text.trim()),
                              if (imageCtrl.text.trim().isNotEmpty)
                                'image_url': imageCtrl.text.trim(),
                            });
                            // stream will auto-update UI
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
                                    backgroundColor: Colors.redAccent),
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

    if (saved == true) {
      // nothing else; StreamBuilder will refresh automatically
    }
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
    height: 140,
    width: double.infinity,
    color: const Color(0xFF0b1220),
    child: const Center(
      child: Icon(Icons.water, color: Colors.white54, size: 28),
    ),
  );
}
