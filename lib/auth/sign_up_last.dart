import 'package:flutter/material.dart';
import './sign_up_data.dart';
import './sign_up_phone.dart';
import '../widgets/step_bar.dart';

class SignUpLastNamePage extends StatefulWidget {
  const SignUpLastNamePage({super.key, required this.data});
  final SignUpData data;

  @override
  State<SignUpLastNamePage> createState() => _SignUpLastNamePageState();
}

class _SignUpLastNamePageState extends State<SignUpLastNamePage> {
  final _last = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() { _last.dispose(); super.dispose(); }

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
      child: StepBar(total: 4, current: 2), // ← set per screen
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
                    "Enter Last Name",
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _last,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Last name",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v==null || v.trim().isEmpty) ? 'Enter your last name' : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        if (!(_form.currentState?.validate() ?? false)) return;
                        widget.data.lastName = _last.text.trim();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SignUpPhonePage(data: widget.data)),
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
