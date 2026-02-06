// lib/widgets/app_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home.dart';
import '../login_page.dart';
import '../theme/rotala_brand.dart';

class AppScaffold extends StatefulWidget {
  final int currentIndex;
  final String title;
  final Widget body;

  // Kept for compatibility with existing HomePage call site
  final String aquaspecNamePrefix;
  final Map<String, dynamic>? initialCredentials;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
    this.aquaspecNamePrefix = 'AquaSpec',
    this.initialCredentials,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _goTab(int index) {
    if (index == widget.currentIndex) return;

    // Keep your existing “coming soon” behavior for sidebar tabs
    if (index == 2 || index == 3) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coming soon'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    HapticFeedback.selectionClick();

    Widget page;
    switch (index) {
      case 0:
        page = const HomePage();
        break;
      default:
        page = const HomePage();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved);
          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    );
  }

  Future<void> _signOut() async {
    HapticFeedback.mediumImpact();

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _showAquaspecComingSoonDialog() async {
    const url = 'https://rotalasystems.com/';

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF111827),
            title: const Text(
              'Connect Device (Coming Soon)',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: const Text(
              'We are currently developing a hardware companion to the app that will sense all of these parameters for you called the AquaSpec.\n\n'
              'If you would like to learn more, please visit:\n'
              'rotalasystems.com',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  Navigator.pop(ctx);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Visit website'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            HapticFeedback.selectionClick();
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Transform.translate(
          offset: const Offset(0, -4),
          child: Image.asset(
            'assets/brand/rotalanew2.png',
            height: 60,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: const [
          SizedBox(width: 8), // keep spacing consistent
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0b1220),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                color: const Color(0xFF111827),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/rotalanew2.png',
                      height: 35,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),

              _DrawerItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: widget.currentIndex == 0,
                onTap: () => _goTab(0),
              ),

              // NEW: Connect Device (Soon)
              _DrawerItem(
                icon: Icons.bluetooth_rounded,
                label: 'Connect Device',
                selected: false,
                comingSoon: true,
                onTap: () async {
                  await _showAquaspecComingSoonDialog();
                },
              ),

              _DrawerItem(
                icon: Icons.smart_toy_rounded,
                label: 'RALA',
                selected: widget.currentIndex == 2,
                comingSoon: true,
                onTap: () => _goTab(2),
              ),
              _DrawerItem(
                icon: Icons.groups_rounded,
                label: 'Community',
                selected: widget.currentIndex == 3,
                comingSoon: true,
                onTap: () => _goTab(3),
              ),

              const Spacer(),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Log out',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: _signOut,
              ),
            ],
          ),
        ),
      ),
      body: widget.body,
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    this.comingSoon = false,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool comingSoon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? RotalaColors.teal : Colors.white70;
    final bg = selected ? const Color(0xFF111827) : Colors.transparent;

    return Material(
      color: bg,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            if (comingSoon) ...[const SizedBox(width: 6), _comingSoonChip()],
          ],
        ),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(); // close drawer
          onTap();
        },
      ),
    );
  }

  Widget _comingSoonChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F4D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Soon',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
