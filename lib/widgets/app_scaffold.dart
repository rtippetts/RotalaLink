import 'package:flutter/material.dart';
import '../home.dart';
import '../devices.dart';
import '../chatbot.dart';
import '../community.dart';
import '../record.dart';
import '../login_page.dart'; // <-- ensure this path is correct

class AppScaffold extends StatefulWidget {
  final int currentIndex; // which tab is active
  final String title;
  final Widget body;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  void _goTab(int index) {
    if (index == widget.currentIndex) return;

    Widget page;
    switch (index) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const DevicesPage();
        break;
      case 2:
        page = const ChatbotPage();
        break;
      case 3:
        page = const CommunityPage();
        break;
      default:
        page = const HomePage();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _signOut(BuildContext context) {
    // Close the drawer
    Navigator.of(context).pop();
    // Navigate to login and clear navigation history
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
    // If you use named routes instead, swap the above for:
    // Navigator.of(context).pushNamedAndRemoveUntil(LoginPage.routeName, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),

      appBar: AppBar(
        backgroundColor: const Color(0xFF1f2937),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        actions: [
          // Use Builder so we get a context below the Scaffold to open the end drawer
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),

      // === Right-side slide-out menu ===
      endDrawer: Drawer(
        backgroundColor: const Color(0xFF111827),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: const BoxDecoration(color: Color(0xFF1f2937)),
                child: const Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white24),

              // Sign out
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white70),
                title: const Text('Sign out',
                    style: TextStyle(color: Colors.white)),
                onTap: () => _signOut(context),
              ),
              const Divider(height: 1, color: Colors.white24),

              // (Optional) add more items here later, e.g. Settings, Profile, etc.
            ],
          ),
        ),
      ),

      body: widget.body,

      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF06b6d4),
        shape: const CircleBorder(),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecordPage()),
          );
        },
        child: const Icon(Icons.fiber_manual_record),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF1f2937),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavBtn(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: widget.currentIndex == 0,
                onTap: () => _goTab(0),
              ),
              _NavBtn(
                icon: Icons.devices_other_rounded,
                label: 'Devices',
                selected: widget.currentIndex == 1,
                onTap: () => _goTab(1),
              ),
              const SizedBox(width: 40), // FAB space
              _NavBtn(
                icon: Icons.smart_toy_rounded,
                label: 'Chatbot',
                selected: widget.currentIndex == 2,
                onTap: () => _goTab(2),
              ),
              _NavBtn(
                icon: Icons.groups_rounded,
                label: 'Community',
                selected: widget.currentIndex == 3,
                onTap: () => _goTab(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? const Color(0xFF06b6d4) : Colors.white70),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF06b6d4) : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
