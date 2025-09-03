import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 1,
      title: "Devices",
      body: const Center(child: Text("Devices screen", style: TextStyle(color: Colors.white))),
    );
  }
}
