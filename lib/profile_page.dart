import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings_page.dart';
import 'theme/rotala_brand.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  String _profileLabel(User? user) {
    if (user == null) return 'User';

    final md = user.userMetadata ?? {};
    final displayName = (md['display_name'] ?? md['username'] ?? '')
        .toString()
        .trim();
    if (displayName.isNotEmpty) return displayName;

    final email = (user.email ?? '').trim();
    if (email.contains('@')) return email.split('@').first;
    return email.isEmpty ? 'User' : email;
  }

  String _profileInitials(User? user) {
    final label = _profileLabel(user);
    final parts = label
        .split(RegExp(r'[\s,_-]+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
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

  Future<void> _shareProfile(BuildContext context, String username) async {
    await Share.share('Check out $username on Rotala.');
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final username = _profileLabel(user);
    final profileImageUrl = _profileImageUrl(user);
    final initials = _profileInitials(user);
    final uid = user?.id;
    final tankStream =
        uid == null
            ? Stream<List<Map<String, dynamic>>>.empty()
            : client
                .from('tanks')
                .stream(primaryKey: ['id'])
                .eq('user_id', uid)
                .order('created_at', ascending: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Share profile',
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            onPressed: () => _shareProfile(context, username),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: tankStream,
        builder: (context, snapshot) {
          final tanks = snapshot.data ?? const <Map<String, dynamic>>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: RotalaColors.teal.withValues(alpha: 0.22),
                    backgroundImage:
                        profileImageUrl != null
                            ? NetworkImage(profileImageUrl)
                            : null,
                    child:
                        profileImageUrl == null
                            ? Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                            : null,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  _StatBlock(
                    label: 'Tanks',
                    value: '${tanks.length}',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareProfile(context, username),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RotalaColors.teal,
                        side: const BorderSide(color: RotalaColors.teal),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Your tanks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tanks.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF122033),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No tanks yet.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              else
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: tanks.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final tank = tanks[index];
                      final imageUrl = (tank['image_url'] ?? '')
                          .toString()
                          .trim();
                      final hasImage =
                          imageUrl.isNotEmpty && imageUrl != 'NULL';

                      return Container(
                        width: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF122033),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child:
                                    hasImage
                                        ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, __, ___) => _tankPlaceholder(),
                                        )
                                        : _tankPlaceholder(),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              right: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  (tank['name'] ?? 'Tank').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tankPlaceholder() {
    return Container(
      color: const Color(0xFF1f2937),
      child: const Center(
        child: Icon(Icons.water_outlined, color: Colors.white38, size: 34),
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
