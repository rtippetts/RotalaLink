import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home.dart';
import 'welcome_page.dart';

class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  bool _loading = true;
  bool _hasSession = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    // Listen for auth changes
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;

      if (!mounted) return;

      setState(() {
        _hasSession = session != null;
      });
    });

    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    setState(() {
      _hasSession = session != null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _hasSession ? const HomePage() : const WelcomePage();
  }
}
