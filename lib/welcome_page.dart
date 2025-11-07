// lib/welcome_page.dart
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'auth/sign_up_first.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme; // <-- ADD THIS BACK
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top wordmark logo instead of text
                  Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Welcome to',
                            textAlign: TextAlign.center,
                            style: textTheme.displaySmall?.copyWith(
                              fontFamily: 'BrandSans',
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF51A7A8), // your brand teal
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 40,
                            child: Image.asset(
                              'assets/brand/rotalalink.png',
                              fit: BoxFit.contain,
                              semanticLabel: 'RotalaLink',
                            ),
                          ),
                        ],
                      ),
                    ),



                  // Square logo hero
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: Container(
                        width: 350,
                        height: 350,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 50,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/brand/rotalafinalsquare2.png', // square logo
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Create account
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpFirstNamePage(),
                          ),
                        );
                      },
                      child: const Text('Create account'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Log in
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      child: const Text('Log in'),
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
