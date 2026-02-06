import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/rotala_brand.dart'; // adjust path if needed
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

const String kWalkthroughSeenKey = 'walkthrough_seen_v1';

class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({super.key});

  /// Mark walkthrough as seen in both local prefs and Supabase user metadata
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWalkthroughSeenKey, true);

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final md = Map<String, dynamic>.from(user.userMetadata ?? {});
        if (md['walkthrough_seen'] != true) {
          md['walkthrough_seen'] = true;
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(data: md),
          );
        }
      } catch (_) {}
    }
  }

  /// Check both Supabase metadata and local prefs
  /// If either says it was seen, we treat it as seen
  static Future<bool> hasSeen() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final md = user.userMetadata ?? {};
      if (md['walkthrough_seen'] == true) {
        return true;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kWalkthroughSeenKey) ?? false;
  }

  /// Helper to show the walkthrough from anywhere (Home, Settings, etc)
  static Future<void> show(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WalkthroughScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final _controller = PageController();
  int _index = 0;

  late final List<_WTPage> _pages = [
    _WTPage(
      icon: MdiIcons.fishbowlOutline, // aquarium icon for Add tank
      title: 'Add your tanks',
      body:
          'Create a tank for each aquarium with its name, size, and water type so Rotala can keep everything organized.',
    ),
    const _WTPage(
      icon: Icons.add_chart,
      title: 'Add parameter readings',
      body:
          'Track your tank chemistry by logging pH, TDS, and temperature for each tank.',
    ),
    const _WTPage(
      icon: Icons.add_task,
      title: 'Set tasks and reminders',
      body:
          'Create tasks for water changes, filter cleanings, and other maintenance so you never miss a step.',
    ),
    const _WTPage(
      icon: Icons.settings,
      title: 'Configure your settings',
      body:
          'Adjust temperature units, notifications, and other preferences. More options, including streaks and badges, are coming soon!',
    ),
  ];

  Future<void> _finish() async {
    await WalkthroughScreen.markSeen();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Skip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            const SizedBox(height: 12),
            _Dots(count: _pages.length, index: _index),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  // Back arrow (disabled and faded on first page)
                  IconButton(
                    onPressed:
                        _index == 0
                            ? null
                            : () {
                              _controller.previousPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            },
                    icon: const Icon(Icons.arrow_back),
                    color: _index == 0 ? Colors.white24 : RotalaColors.teal,
                  ),
                  const Spacer(),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: RotalaColors.teal,
                      ),
                      onPressed:
                          last
                              ? _finish
                              : () {
                                _controller.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              },
                      child: Text(last ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _WTPage extends StatelessWidget {
  const _WTPage({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: RotalaColors.teal),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: active ? 22 : 8,
          decoration: BoxDecoration(
            color: active ? RotalaColors.teal : Colors.white24,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}
