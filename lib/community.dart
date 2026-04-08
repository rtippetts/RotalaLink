import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 1,
      title: 'Think Tank',
      body: const Center(
        child: Text('Think Tank screen', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
