// lib/auth/sign_up_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home.dart';
import '../widgets/otp_code.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // stages: form -> verify
  String _stage = 'form';

  final _formKey = GlobalKey<FormState>();

  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String _otpCollected = '';

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _alert(String title, String message) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  bool _looksLikeEmail(String v) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());

  Future<void> _startSignUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _displayName.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;

    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      await client.auth.signUp(
        email: email,
        password: pass,
        data: {
          // Store it as display_name (and also username for future flexibility)
          'display_name': name,
          'username': name,
        },
      );

      if (!mounted) return;

      setState(() {
        _stage = 'verify';
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We emailed you a 6 digit code. Enter it to verify.'),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _loading = false);
      _alert("Sign up failed", e.message);
    } catch (e) {
      setState(() => _loading = false);
      _alert("Unexpected error", e.toString());
    }
  }

  Future<void> _verifyCode() async {
    final email = _email.text.trim();
    final code = _otpCollected.trim();

    if (code.length < 6) {
      _alert("Invalid code", "Enter the 6 digit code we sent to your email.");
      return;
    }

    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      await client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );

      // Sign in after verification so you have a session
      final res = await client.auth.signInWithPassword(
        email: email,
        password: _password.text,
      );

      if (res.user == null) {
        throw Exception('Sign in failed after verification.');
      }

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    } on AuthException catch (e) {
      setState(() => _loading = false);
      _alert("Verification failed", e.message);
    } catch (e) {
      setState(() => _loading = false);
      _alert("Unexpected error", e.toString());
    }
  }

  Future<void> _resendCode() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      await client.auth.resend(type: OtpType.signup, email: _email.text.trim());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code resent. Check your email.')),
      );
    } catch (e) {
      _alert('Could not resend code', e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          height: 50,
          child: Image.asset(
            'assets/brand/rotalanew2.png',
            fit: BoxFit.contain,
            semanticLabel: 'Rotala',
          ),
        ),
      ),
      body: Align(
        alignment: const Alignment(0, -0.45),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero logo (same look you already have)
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
                  _stage == 'form' ? "Create Account" : "Check your email",
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(
                    color: const Color(0xFF51A7A8),
                    fontFamily: 'BrandSans',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  _stage == 'form'
                      ? "Let’s get you set up."
                      : "Enter the 6 digit code we sent to ${_email.text.trim()} to verify your account.",
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    fontFamily: 'BrandSans',
                  ),
                ),

                const SizedBox(height: 24),

                if (_stage == 'form') ...[
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // “What should we call you?”
                        TextFormField(
                          controller: _displayName,
                          textCapitalization: TextCapitalization.words,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: "Name",
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return 'Please enter a name';
                            if (s.length < 2) return 'Too short';
                            if (s.length > 24)
                              return 'Keep it under 24 characters';
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Email
                        TextFormField(
                          controller: _email,
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          decoration: const InputDecoration(
                            labelText: "Email",
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return 'Enter your email';
                            if (!_looksLikeEmail(s))
                              return 'Enter a valid email';
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextFormField(
                          controller: _password,
                          enabled: !_loading,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: "Password (12+ chars)",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed:
                                  _loading
                                      ? null
                                      : () =>
                                          setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip:
                                  _obscure ? "Show password" : "Hide password",
                            ),
                          ),
                          validator: (v) {
                            final s = v ?? '';
                            if (s.length < 12)
                              return 'Password must be at least 12 characters';
                            return null;
                          },
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted:
                              (_) => _loading ? null : _startSignUp(),
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: _loading ? null : _startSignUp,
                            child:
                                _loading
                                    ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text("Sign Up"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // OTP stage
                  OtpCode(
                    length: 6,
                    onChanged: (v) => _otpCollected = v,
                    onCompleted: (v) => _otpCollected = v,
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _verifyCode,
                      child:
                          _loading
                              ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text("Verify & Continue"),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: _loading ? null : _resendCode,
                    child: const Text('Resend code'),
                  ),

                  // Optional: if they want to edit email/password/name
                  TextButton(
                    onPressed:
                        _loading
                            ? null
                            : () => setState(() {
                              _stage = 'form';
                              _otpCollected = '';
                            }),
                    child: const Text('Edit info'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
