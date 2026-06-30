import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'auth/reset_password.dart';
import 'login_page.dart';
import 'onboarding/walkthrough.dart';
import 'tank_export.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    AppSettings.load();
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _Section(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: AppSettings.themeMode,
                      builder: (context, themeMode, _) {
                        return SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            AppSettings.setThemeMode(selection.first);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.useFahrenheit,
                builder: (context, useFahrenheit, _) {
                  return SwitchListTile(
                    value: useFahrenheit,
                    onChanged: AppSettings.setUseFahrenheit,
                    title: const Text('Temperature units'),
                    subtitle: Text(useFahrenheit ? 'Using F' : 'Using C'),
                  );
                },
              ),
              const Divider(height: 1),
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.useGallons,
                builder: (context, useGallons, _) {
                  return SwitchListTile(
                    value: useGallons,
                    onChanged: AppSettings.setUseGallons,
                    title: const Text('Tank volume units'),
                    subtitle: Text(
                      useGallons ? 'Using gallons' : 'Using liters',
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            children: [
              ListTile(
                leading: Icon(
                  Icons.school_outlined,
                  color: cs.onSurfaceVariant,
                ),
                title: const Text('View app walkthrough'),
                subtitle: const Text('See the quick tour again'),
                onTap: () => WalkthroughScreen.show(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.lock_reset, color: cs.onSurfaceVariant),
                title: const Text('Reset password'),
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ResetPasswordPage(),
                      ),
                    ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.file_download_outlined,
                  color: cs.onSurfaceVariant,
                ),
                title: const Text('Export tank data (CSV)'),
                subtitle: const Text('Download and share your tank readings'),
                onTap: () => exportTankData(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline),
      ),
      child: Column(children: children),
    );
  }
}
