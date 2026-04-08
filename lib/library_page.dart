import 'package:flutter/material.dart';

import 'widgets/app_scaffold.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 3,
      title: 'Library',
      body: const Center(
        child: Text(
          'Library screen',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
