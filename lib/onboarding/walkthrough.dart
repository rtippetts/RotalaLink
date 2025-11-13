import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kWalkthroughSeenKey = 'walkthrough_seen_v1';

class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({super.key});

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWalkthroughSeenKey, true);

    // Optional: persist per user so it never shows on other devices once seen
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final md = Map<String, dynamic>.from(user.userMetadata ?? {});
        if (md['walkthrough_seen'] != true) {
          md['walkthrough_seen'] = true;
          await Supabase.instance.client.auth.updateUser(UserAttributes(data: md));
        }
      } catch (_) {}
    }
  }

  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getBool(kWalkthroughSeenKey) ?? false;

    if (local) return true;

    // If signed in and metadata says seen, sync local flag and honor it
    final user = Supabase.instance.client.auth.currentUser;
    final remote = user?.userMetadata?['walkthrough_seen'] == true;
    if (remote) {
      await prefs.setBool(kWalkthroughSeenKey, true);
      return true;
    }
    return false;
  }

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final _controller = PageController();
  int _index = 0;

  final _pages = const [
    _WTPage(
      icon: Icons.water_drop,
      title: 'Track your tanks',
      body: 'Add each tank and record pH, TDS, and temperature.',
    ),
    _WTPage(
      icon: Icons.notifications,
      title: 'Stay ahead of issues',
      body: 'See alerts and handle problems before they get serious.',
    ),
    _WTPage(
      icon: Icons.add_chart,
      title: 'Add readings fast',
      body: 'Use Quick Actions to log tests in seconds.',
    ),
    _WTPage(
      icon: Icons.grid_view,
      title: 'Choose your layout',
      body: 'Switch between grid, list, or full cards.',
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
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _finish,
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: last
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
          Icon(icon, size: 96, color: Colors.cyanAccent),
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
            color: active ? Colors.cyanAccent : Colors.white24,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}
