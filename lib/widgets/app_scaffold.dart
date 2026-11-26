import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile_page.dart';
import '../settings_page.dart';
import '../theme/rotala_brand.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
    this.overlay,
    this.leadingSecondary,
    this.actions,
    this.onRecord,
    this.onTasks,
    this.aquaspecNamePrefix = 'AquaSpec',
    this.initialCredentials,
  });

  // Retained for the separate hardware screens. Store navigation uses the
  // completed aquarium-management actions below.
  final int currentIndex;
  final String title;
  final Widget body;
  final Widget? overlay;
  final Widget? leadingSecondary;
  final List<Widget>? actions;
  final VoidCallback? onRecord;
  final VoidCallback? onTasks;
  final String aquaspecNamePrefix;
  final Map<String, dynamic>? initialCredentials;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? {};
    final displayName = (metadata['display_name'] ?? metadata['username'] ?? '')
        .toString()
        .trim();
    final email = user?.email ?? '';
    final label = displayName.isNotEmpty ? displayName : email.split('@').first;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            leadingWidth: leadingSecondary == null ? 72 : 120,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: label.isEmpty
                        ? 'Open profile'
                        : 'Open profile for $label',
                    icon: Icon(Icons.person_outline, color: cs.onSurface),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfilePage(),
                        ),
                      );
                    },
                  ),
                  if (leadingSecondary != null) leadingSecondary!,
                ],
              ),
            ),
            title: Text(title),
            centerTitle: true,
            actions: [...?actions, const SizedBox(width: 8)],
          ),
          body: body,
          bottomNavigationBar: onRecord == null
              ? null
              : SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: onTasks,
                          icon: const Icon(Icons.checklist_rounded),
                          label: const Text('Tasks'),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            backgroundColor: RotalaColors.teal,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: onRecord,
                          icon: const Icon(Icons.add_chart),
                          label: const Text('Record'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsPage(),
                            ),
                          ),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Settings'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (overlay != null) overlay!,
      ],
    );
  }
}
