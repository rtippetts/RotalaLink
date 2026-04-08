import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chatbot.dart';
import '../community.dart';
import '../home.dart';
import '../library_page.dart';
import '../profile_page.dart';
import '../theme/rotala_brand.dart';

class AppScaffold extends StatefulWidget {
  final int currentIndex;
  final String title;
  final Widget body;
  final Widget? overlay;
  final Widget? leadingSecondary;
  final List<Widget>? actions;
  final String aquaspecNamePrefix;
  final Map<String, dynamic>? initialCredentials;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
    this.overlay,
    this.leadingSecondary,
    this.actions,
    this.aquaspecNamePrefix = 'AquaSpec',
    this.initialCredentials,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  String _profileLabel(User? user) {
    if (user == null) return '';

    final md = user.userMetadata ?? {};
    final displayName = (md['display_name'] ?? md['username'] ?? '')
        .toString()
        .trim();
    if (displayName.isNotEmpty) return displayName;

    final email = (user.email ?? '').trim();
    if (email.contains('@')) return email.split('@').first;
    return email;
  }

  String _profileInitials(User? user) {
    final label = _profileLabel(user);
    if (label.isEmpty) return 'U';

    final parts = label
        .split(RegExp(r'[\s,_-]+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return label.substring(0, 1).toUpperCase();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String? _profileImageUrl(User? user) {
    if (user == null) return null;

    final md = user.userMetadata ?? {};
    for (final key in const ['avatar_url', 'picture', 'photo_url']) {
      final value = (md[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _openProfile() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  Widget _pageForIndex(int index) {
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return const CommunityPage();
      case 2:
        return const ChatbotPage();
      case 3:
        return const LibraryPage();
      default:
        return const HomePage();
    }
  }

  Future<void> _goTab(int index) async {
    if (index == widget.currentIndex) return;

    HapticFeedback.selectionClick();

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _pageForIndex(index),
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  Future<void> _openRecordSheet() async {
    HapticFeedback.mediumImpact();

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    List<Map<String, dynamic>> tanks = const [];

    if (uid != null) {
      try {
        final rows = await client
            .from('tanks')
            .select('id,name')
            .eq('user_id', uid)
            .order('created_at');
        tanks = List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {}
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF122033),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Record',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose a tank or scan an RFID tag to start recording.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: RotalaColors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        icon: const Icon(Icons.playlist_add_check_circle_outlined),
                        label: const Text('Select tank'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).maybePop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('RFID scanning is still in development'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.nfc_rounded),
                        label: const Text('Scan RFID'),
                      ),
                    ),
                  ],
                ),
                if (tanks.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Your tanks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: tanks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final tank = tanks[index];
                        return ListTile(
                          tileColor: const Color(0xFF0b1220),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF1f2937),
                            child: Icon(Icons.water, color: Colors.white70),
                          ),
                          title: Text(
                            (tank['name'] ?? 'Tank').toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Colors.white54,
                          ),
                          onTap: () {
                            Navigator.of(ctx).maybePop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Recording flow for ${(tank['name'] ?? 'Tank')} is next.',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = widget.currentIndex == index;
    final color = selected ? RotalaColors.teal : Colors.white70;

    return Expanded(
      child: InkWell(
        onTap: () => _goTab(index),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final profileImageUrl = _profileImageUrl(user);
    final profileInitials = _profileInitials(user);
    final profileLabel = _profileLabel(user);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF0b1220),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0b1220),
            elevation: 0,
            leadingWidth: widget.leadingSecondary == null ? 72 : 120,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip:
                        profileLabel.isEmpty
                            ? 'Open profile'
                            : 'Open profile for $profileLabel',
                    padding: EdgeInsets.zero,
                    icon: CircleAvatar(
                      radius: 18,
                      backgroundColor: RotalaColors.teal.withValues(alpha: 0.22),
                      backgroundImage:
                          profileImageUrl != null
                              ? NetworkImage(profileImageUrl)
                              : null,
                      child:
                          profileImageUrl == null
                              ? Text(
                                profileInitials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              )
                              : null,
                    ),
                    onPressed: _openProfile,
                  ),
                  if (widget.leadingSecondary != null) ...[
                    const SizedBox(width: 2),
                    widget.leadingSecondary!,
                  ],
                ],
              ),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [
              ...?widget.actions,
              const SizedBox(width: 8),
            ],
          ),
          body: widget.body,
          bottomNavigationBar: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 60,
                    color: const Color(0xFF101827),
                    child: Row(
                      children: [
                        _navItem(index: 0, icon: Icons.home_rounded, label: 'Home'),
                        _navItem(index: 1, icon: Icons.groups_rounded, label: 'Think Tank'),
                        const SizedBox(width: 64),
                        _navItem(index: 2, icon: Icons.smart_toy_rounded, label: 'RALA'),
                        _navItem(index: 3, icon: Icons.menu_book_rounded, label: 'Library'),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -22,
                    child: Container(
                      height: 62,
                      width: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: RotalaColors.teal.withValues(alpha: 0.24),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FloatingActionButton(
                        backgroundColor: RotalaColors.teal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const CircleBorder(),
                        onPressed: _openRecordSheet,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }
}
