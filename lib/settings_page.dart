import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'auth/reset_password.dart';
import 'login_page.dart';
import 'onboarding/walkthrough.dart';
import 'tank_export.dart';
import 'theme/rotala_brand.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF122033),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.useFahrenheit,
                  builder: (context, useFahrenheit, _) {
                    return SwitchListTile(
                      value: useFahrenheit,
                      onChanged: AppSettings.setUseFahrenheit,
                      title: const Text(
                        'Temperature units',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        useFahrenheit ? 'Using F' : 'Using C',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      activeColor: RotalaColors.teal,
                    );
                  },
                ),
                const Divider(height: 1, color: Colors.white12),
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.useGallons,
                  builder: (context, useGallons, _) {
                    return SwitchListTile(
                      value: useGallons,
                      onChanged: AppSettings.setUseGallons,
                      title: const Text(
                        'Tank volume units',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        useGallons ? 'Using gallons' : 'Using liters',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      activeColor: RotalaColors.teal,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF122033),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.school_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'View app walkthrough',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'See the quick tour again',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () => WalkthroughScreen.show(context),
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  leading: const Icon(
                    Icons.lock_reset,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Reset password',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ResetPasswordPage(),
                        ),
                      ),
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  leading: const Icon(
                    Icons.file_download_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Export tank data (CSV)',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Download and share your tank readings',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () => exportTankData(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
