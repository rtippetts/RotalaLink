import 'package:flutter/material.dart';

class RecordPage extends StatelessWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1f2937),
        title: const Text('Record Measurement', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: const Center(child: Text('Record screen', style: TextStyle(color: Colors.white))),
    );
  }
}
