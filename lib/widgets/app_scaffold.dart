import 'package:flutter/material.dart';
import '../home.dart';
import '../devices.dart';
import '../chatbot.dart';
import '../community.dart';
import '../login_page.dart';
import '../profile_page.dart';

class AppScaffold extends StatefulWidget {
  final int currentIndex;
  final String title; // kept for compatibility, not shown when logo is present
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _goTab(int index) {
    if (index == widget.currentIndex) {
      Navigator.of(context).maybePop();
      return;
    }

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

  void _signOut() {
    Navigator.of(context).pop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF111827),

      appBar: AppBar(
        backgroundColor: const Color(0xFF1f2937),
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),

        // Show your RotalaLink wordmark instead of "Welcome, user"
       title: Transform.translate(
        offset: const Offset(0, -4), // move up a few pixels
        child: Image.asset(
             'assets/brand/rotalanew2.png',
        height: 65,
        fit: BoxFit.contain,
      ),
    ),
      centerTitle: true,
        

        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_rounded, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      drawer: Drawer(
        backgroundColor: const Color(0xFF111827),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                color: const Color(0xFF1f2937),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/rotalalink.png',
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
              _DrawerItem(
                icon: Icons.devices_other_rounded,
                label: 'Devices',
                selected: widget.currentIndex == 1,
                onTap: () => _goTab(1),
              ),
              _DrawerItem(
                icon: Icons.smart_toy_rounded,
                label: 'Chatbot',
                selected: widget.currentIndex == 2,
                onTap: () => _goTab(2),
              ),
              _DrawerItem(
                icon: Icons.groups_rounded,
                label: 'Community',
                selected: widget.currentIndex == 3,
                onTap: () => _goTab(3),
              ),

              const Spacer(),
              const Divider(height: 1, color: Colors.white24),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white70),
                title: const Text('Sign out', style: TextStyle(color: Colors.white)),
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF06b6d4) : Colors.white70;
    final bg = selected ? const Color(0xFF0b1220) : Colors.transparent;

    return Material(
      color: bg,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }
}
