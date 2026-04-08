import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';

class ChatbotPage extends StatelessWidget {
  const ChatbotPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 2,
      title: 'RALA',
      body: const Center(
        child: Text('RALA screen', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
