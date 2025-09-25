// lib/welcome_page.dart
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'auth/sign_up_first.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                  // Title in upper-middle, styled like Create Account
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Welcome to RotalaLink!',
                        textAlign: TextAlign.center,
                        style: textTheme.displaySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  // Big image / hero area
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cs.surface,
                            border: Border.all(color: cs.outline),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          // Replace with your asset if desired:
                          // child: Image.asset('assets/illustrations/welcome.png', fit: BoxFit.cover),
                          child: Icon(Icons.water_drop_outlined, size: 120, color: cs.primary),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Primary CTA
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignUpFirstNamePage()),
                        );
                      },
                      child: const Text('Create account'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Secondary CTA
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
                  const Spacer(flex: 1)
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
