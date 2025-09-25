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
  void dispose() { _first.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
  title: const Text('Create account'),
  centerTitle: true,
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: StepBar(total: 4, current: 1), // ← set per screen
    ),
  ),
),
      body: Align(
                  alignment: const Alignment(0, -0.45), // -1 = top, 0 = center
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Enter First Name",
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _first,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "First name",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v==null || v.trim().isEmpty) ? 'Enter your first name' : null,
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
                          MaterialPageRoute(builder: (_) => SignUpLastNamePage(data: data)),
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
