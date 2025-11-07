// lib/auth/sign_up_phone.dart
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

  // Keep this small and focused; expand as needed.
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
    // Default to prior value or +1
    _countryCode = widget.data.countryCode.isNotEmpty ? widget.data.countryCode : '+1';
    // If you previously captured a local phone, show it
    if (widget.data.phoneLocal.isNotEmpty) {
      _phoneCtrl.text = widget.data.phoneLocal;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

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
            child: StepBar(total: 4, current: 3),
          ),
        ),
      ),
      body: Align(
        alignment: const Alignment(0, -0.45), // keep higher in the viewport
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand square logo hero for visual consistency
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
                    "Enter Phone Number",
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      color: const Color(0xFF51A7A8), // brand teal
                      fontFamily: 'BrandSans',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We will only use this for important alerts.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      fontFamily: 'BrandSans',
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Country code + phone number
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          value: _countryCode,
                          dropdownColor: const Color(0xFF0b1220),
                          decoration: const InputDecoration(labelText: 'Code'),
                          items: _codes
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _countryCode = v ?? '+1';
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                        final codeDigits = _digitsOnly(_countryCode);

                        widget.data.countryCode = _countryCode;
                        widget.data.phoneLocal = localDigits;
                        widget.data.phone = '$codeDigits$localDigits'; // digits only E.164-ish

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SignUpAuthPage(data: widget.data),
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
