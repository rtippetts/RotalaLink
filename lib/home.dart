import 'package:flutter/material.dart';
import 'widgets/app_scaffold.dart';
import 'tank_detail_page.dart'; // import the TankDetailPage we created

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentIndex: 0, // Home tab selected
      title: "Welcome, user",

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Dashboard card =====
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1f2937),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Dashboard",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),

                  // Alerts
                  Text("Alerts",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text("• pH level too low in Tank 2",
                      style: TextStyle(color: Colors.white)),
                  Text("• Temperature high in Tank 4",
                      style: TextStyle(color: Colors.white)),

                  SizedBox(height: 16),

                  // Tasks
                  Text("Tasks",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text("• Clean filter in Tank 1",
                      style: TextStyle(color: Colors.white)),
                  Text("• Change water in Tank 3",
                      style: TextStyle(color: Colors.white)),

                  SizedBox(height: 16),

                  // Connection
                  Text("Connection Status",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text("• All devices connected",
                      style: TextStyle(color: Colors.greenAccent)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ===== Tanks header =====
            const Text(
              "Your Tanks",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // ===== Bigger horizontal tank cards =====
            SizedBox(
              height: 240, // card height
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 8,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final tank = Tank(
                    id: 'tank${index + 1}',
                    name: 'Tank ${index + 1}',
                    volumeLiters: 100, // demo placeholder
                    inhabitants: 'Freshwater community',
                  );

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TankDetailPage(tank: tank),
                        ),
                      );
                    },
                    child: Container(
                      width: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1f2937),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                            child: Image.network(
                              'https://images.unsplash.com/photo-1605131267021-81bdc7c59e9b?fit=crop&w=600&q=80',
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'Tank ${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'Freshwater',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
