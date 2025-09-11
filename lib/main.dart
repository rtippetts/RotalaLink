import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart'; // 👈 Import your login page

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize supabase once at startup
  await Supabase.initialize(
    url: 'https://dbflovgjvzqjejekflg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRiZmdsb3ZnanV6cWllamVrZmxnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM4ODI2NzQsImV4cCI6MjA1OTQ1ODY3NH0.mzRht4dDiCC9GQlX_5c1K_UJKWXvKeAHPBHqBVNsHvU',
  );

  runApp(const MyApp());
}





class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RotalaLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(), // 👈 Set LoginPage as the home screen
    );
  }
}
