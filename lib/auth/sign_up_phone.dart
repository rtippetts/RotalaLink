import 'package:flutter/material.dart';
import './sign_up_data.dart';
import './sign_up_auth.dart';
import '../widgets/step_bar.dart';

class SignUpPhonePage extends StatefulWidget {
  const SignUpPhonePage({super.key, required this.data});
  final SignUpData data;

  @override
  State<SignUpPhonePage> createState() => _SignUpPhonePageState();
}

class _SignUpPhonePageState extends State<SignUpPhonePage> {
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // A small, sane set. Add more as needed.
  static const _codes = <String>[
    '+1',  // US/CA
    '+44', // UK
    '+61', // AU
    '+91', // IN
    '+81', // JP
    '+49', // DE
  ];

  late String _countryCode;

  @override
  void initState() {
    super.initState();
    _countryCode = widget.data.countryCode;
  }

  @override
  void dispose() { _phoneCtrl.dispose(); super.dispose(); }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

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
      child: StepBar(total: 4, current: 3), // ← set per screen
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
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Enter Phone Number",
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),

                  // Country code + free-form number
                  Row(
                    children: [
                      // Country code dropdown
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          value: _countryCode,
                          decoration: const InputDecoration(labelText: 'Code'),
                          items: _codes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setState(() => _countryCode = v ?? '+1'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Free-form phone input
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: "Phone number",
                            hintText: "e.g., (303) 555-0123",
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (v) {
                            final digits = _digitsOnly(v ?? '');
                            if (digits.isEmpty) return 'Enter your phone number';
                            if (digits.length < 7) return 'Enter a valid phone number';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        if (!(_formKey.currentState?.validate() ?? false)) return;

                        final localDigits = _digitsOnly(_phoneCtrl.text);
                        final codeDigits  = _digitsOnly(_countryCode);
                        // Save all pieces
                        widget.data.countryCode = _countryCode;
                        widget.data.phoneLocal  = localDigits;
                        widget.data.phone       = '$codeDigits$localDigits'; // digits only

                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SignUpAuthPage(data: widget.data)),
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
