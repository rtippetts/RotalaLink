import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 3,
      title: "Community",
      body: const Center(child: Text("Community screen", style: TextStyle(color: Colors.white))),
    );
  }
}
