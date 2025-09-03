import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Forgot Password", style: TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Forgot Password placeholder — we’ll build this next.",
            style: TextStyle(color: Color(0xFF9ca3af)),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
