import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // match system brightness
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart'; // 👈 Import your login page
import 'welcome_page.dart'; // import welcome page
import 'ui/aqua_theme.dart';
import 'ui/aqua_schemes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize supabase once at startup
  await Supabase.initialize(
    url: 'https://dbfglovgjuzqiejekflg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRiZmdsb3ZnanV6cWllamVrZmxnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM4ODI2NzQsImV4cCI6MjA1OTQ1ODY3NH0.mzRht4dDiCC9GQlX_5c1K_UJKWXvKeAHPBHqBVNsHvU',
  );

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  
@override
Widget build(BuildContext context) {
  final cs = oceanCore; // or use MediaQuery to detect dark mode
  SystemChrome.setSystemUIOverlayStyle(
    cs.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
  );

  return MaterialApp(
    title: 'RotalaLink',
    theme: aquaTheme(oceanCore),
    darkTheme: aquaTheme(deepSeaDark),
    themeMode: ThemeMode.system,
    home: const WelcomePage(),
  );
}
}
