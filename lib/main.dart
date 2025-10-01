import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // match system brightness
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';
import 'welcome_page.dart';
import 'auth/reset_password.dart';
import 'ui/aqua_schemes.dart';
import 'ui/aqua_theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize supabase once at startup
  await Supabase.initialize(
    url: 'https://dbfglovgjuzqiejekflg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRiZmdsb3ZnanV6cWllamVrZmxnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM4ODI2NzQsImV4cCI6MjA1OTQ1ODY3NH0.mzRht4dDiCC9GQlX_5c1K_UJKWXvKeAHPBHqBVNsHvU',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A) Ocean Core  |  B) Coral Lead  |  C) Deep Blue
    final light = oceanCoreLight;  // or coralLeadLight, deepBlueLight
    final dark  = oceanCoreDark;   // or coralLeadDark,  deepBlueDark

    return MaterialApp(
      navigatorKey: navigatorKey, // 👈 important!
      title: 'RotalaLink',
      theme: aquaTheme(light),
      darkTheme: aquaTheme(dark),
      themeMode: ThemeMode.system,
      home: const WelcomePage(),
    );
  }
}
