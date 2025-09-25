// lib/auth/sign_up_auth.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home.dart';
import './sign_up_data.dart';
import '../widgets/otp_code.dart';
import '../widgets/step_bar.dart';

class SignUpAuthPage extends StatefulWidget {
  const SignUpAuthPage({super.key, required this.data});
  final SignUpData data;

  @override
  State<SignUpAuthPage> createState() => _SignUpAuthPageState();
}

class _SignUpAuthPageState extends State<SignUpAuthPage> {
  // 'form' => email/password entry, 'verify' => OTP entry
  String _stage = 'form';

  final _email = TextEditingController();
  final _password = TextEditingController();

  String _otpCollected = '';

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _alert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  Future<void> _startSignUp() async {
    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      _alert("Invalid email", "Enter a valid email address.");
      return;
    }
    if (pass.length < 12) {
      _alert("Weak password", "Password must be at least 12 characters.");
      return;
    }

    setState(() => _loading = true);
    final client = Supabase.instance.client;

    final displayName = "${widget.data.lastName.trim()}, ${widget.data.firstName.trim()}";

    try {
      // Confirmation is ON; no session expected here.
      await client.auth.signUp(
        email: email,
        password: pass,
        data: {
          'display_name': displayName,
          'phone': widget.data.phone,   // digits-only from phone step
          'first_name': widget.data.firstName,
          'last_name': widget.data.lastName,
        },
      );

      if (!mounted) return;

      setState(() {
        _stage = 'verify';
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We emailed you a 6-digit code. Enter it to verify.')),
      );
    } on AuthException catch (e) {
      setState(() => _loading = false);
      _alert("Sign up failed", e.message);
    } catch (e) {
      setState(() => _loading = false);
      _alert("Unexpected error", e.toString());
    }
  }

  Future<void> _verifyCode({required String code}) async {
    final email = _email.text.trim();
    if (code.length < 6) {
      _alert("Invalid code", "Enter the 6-digit code we sent to your email.");
      return;
    }

    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      // 1) Verify email OTP
      await client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );

      // 2) Sign in with password (creates session)
      final signInRes = await client.auth.signInWithPassword(
        email: email,
        password: _password.text,
      );
      if (signInRes.user == null) {
        throw Exception('Sign-in failed after verification.');
      }

      if (!mounted) return;
      // 3) Go to Home
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
      await client.auth.resend(
        type: OtpType.signup,          // resend for email confirmations
        email: _email.text.trim(),
      );
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
  title: const Text('Create account'),
  centerTitle: true,
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: StepBar(total: 4, current: 4), // ← set per screen
    ),
  ),
),
      body: Align(
        alignment: const Alignment(0, -0.45), // move content toward upper middle
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _stage == 'form'
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Create Account",
                        style: textTheme.displaySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Email
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: "Email",
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        enabled: !_loading,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),

                      // Password (single field)
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: "Password (12+ chars)",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: _loading ? null : () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            tooltip: _obscure ? "Show password" : "Hide password",
                          ),
                        ),
                        enabled: !_loading,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _loading ? null : _startSignUp(),
                      ),

                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _loading ? null : _startSignUp,
                          child: _loading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text("Sign Up"),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Check your email",
                        style: textTheme.titleLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Enter the 6-digit code we sent to ${_email.text.trim()} to verify your account.",
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(.75)),
                      ),
                      const SizedBox(height: 24),

                      // 6-box OTP UI
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
                          onPressed: _loading ? null : () => _verifyCode(code: _otpCollected),
                          child: _loading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text("Verify & Continue"),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: _loading ? null : _resendCode,
                        child: const Text('Resend code'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
