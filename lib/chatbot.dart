import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';

class ChatbotPage extends StatelessWidget {
  const ChatbotPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 2,
      title: "Chatbot",
      body: const Center(child: Text("Chatbot screen", style: TextStyle(color: Colors.white))),
    );
  }
}
