// lib/auth/sign_up_first.dart
import 'package:flutter/material.dart';
import './sign_up_data.dart';
import './sign_up_last.dart';
import '../widgets/step_bar.dart';

class SignUpFirstNamePage extends StatefulWidget {
  const SignUpFirstNamePage({super.key});

  @override
  State<SignUpFirstNamePage> createState() => _SignUpFirstNamePageState();
}

class _SignUpFirstNamePageState extends State<SignUpFirstNamePage> {
  final _first = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        centerTitle: true,
        title: SizedBox(
          height: 28,
          child: Image.asset(
            'assets/brand/rotalalink.png', // wordmark logo
            fit: BoxFit.contain,
            semanticLabel: 'RotalaLink',
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(10),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: StepBar(total: 4, current: 1),
          ),
        ),
      ),
      body: Align(
        alignment: const Alignment(0, -0.45),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Square logo hero
                  Center(
                    child: Hero(
                      tag: 'brandHero',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/brand/rotalafinalsquare2.png',
                          width: 300,
                          height: 300,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    "Enter First Name",
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      color: const Color(0xFF51A7A8),
                      fontFamily: 'BrandSans',
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  // *Subtle cue, optional but recommended*
                  const SizedBox(height: 8),
                  Text(
                    "This will help personalize your experience.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      fontFamily: 'BrandSans',
                    ),
                  ),

                  const SizedBox(height: 28),

                  TextFormField(
                    controller: _first,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "First name",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your first name' : null,
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        if (!(_form.currentState?.validate() ?? false)) return;
                        final data = SignUpData()..firstName = _first.text.trim();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SignUpLastNamePage(data: data),
                          ),
                        );
                      },
                      child: const Text("Continue"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
