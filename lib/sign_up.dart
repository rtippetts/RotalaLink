import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../login_page.dart'; // adjust path if needed

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

enum _SignUpStep { email, code, password }

class _SignUpPageState extends State<SignUpPage> {
  _SignUpStep _step = _SignUpStep.email;

  // Controllers
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  // Focus nodes
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _pwdFocus = FocusNode();

  // State
  bool _isLoading = false;
  String? _error;
  String? _sentToEmail;
  String? _expectedCode;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _pwdCtrl.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  // === Utils ===
  bool _validEmail(String v) {
    final email = v.trim();
    // simple but effective email check
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(email);
  }

  String _generate6DigitCode() {
    final rng = Random.secure();
    return (rng.nextInt(900000) + 100000).toString();
  }

  void _startResendCooldown([int seconds = 30]) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  // === Actions ===
  Future<void> _sendVerificationCode() async {
    final email = _emailCtrl.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = "Please enter a valid email.");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // TODO: Replace this with your backend call to send an email with the code.
      // Example: await api.sendVerificationCode(email);
      await Future.delayed(const Duration(milliseconds: 600));

      final code = _generate6DigitCode();
      _expectedCode = code;
      _sentToEmail = email;

      // For dev/testing only: log the code so you can try it.
      // Remove this in production.
      // ignore: avoid_print
      print("DEBUG: Verification code for $email is $code");

      if (!mounted) return;
      setState(() {
        _step = _SignUpStep.code;
      });
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification code sent. Check your email.")),
      );
      // Move focus to code field
      await Future.delayed(const Duration(milliseconds: 100));
      _codeFocus.requestFocus();
    } catch (e) {
      setState(() => _error = "Failed to send code. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final entered = _codeCtrl.text.trim();
    if (entered.length != 6 || int.tryParse(entered) == null) {
      setState(() => _error = "Enter the 6-digit code.");
      return;
    }
    if (entered != _expectedCode) {
      setState(() => _error = "Incorrect code. Try again.");
      return;
    }

    setState(() {
      _error = null;
      _step = _SignUpStep.password;
    });

    await Future.delayed(const Duration(milliseconds: 80));
    _pwdFocus.requestFocus();
  }

  Future<void> _saveAccount() async {
    final pwd = _pwdCtrl.text;
    if (pwd.length < 12) {
      setState(() => _error = "Password must be at least 12 characters.");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // TODO: Replace with your real persistence:
      // - Call your backend to create the account (email + password)
      // - Or store a session token, etc.
      // Example:
      // await api.createAccount(email: _sentToEmail!, password: pwd);

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created. Please log in.")),
      );

      // Redirect to login and clear history
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Could not create account. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _sentToEmail == null) return;
    // Reuse the same flow, but keep the same email.
    setState(() {
      _emailCtrl.text = _sentToEmail!;
      _step = _SignUpStep.email; // go through send flow again for consistency
    });
    await _sendVerificationCode();
  }

  // === UI Builders ===
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ScreenTitle("Enter your email"),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration("Email"),
          onSubmitted: (_) => _sendVerificationCode(),
        ),
        const SizedBox(height: 16),
        _PrimaryBtn(
          label: "Send code",
          onPressed: _isLoading ? null : _sendVerificationCode,
          loading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScreenTitle("Check your email"),
        const SizedBox(height: 4),
        Text(
          _sentToEmail == null
              ? "We sent you a 6-digit code."
              : "We sent a 6-digit code to\n$_sentToEmail",
          style: const TextStyle(color: Color(0xFF9ca3af)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeCtrl,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration("Enter 6-digit code").copyWith(
            counterText: "",
          ),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _PrimaryBtn(
              label: "Verify",
              onPressed: _isLoading ? null : _verifyCode,
              loading: _isLoading,
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: (_secondsLeft == 0 && !_isLoading) ? _resend : null,
              child: Text(
                _secondsLeft == 0 ? "Resend code" : "Resend in $_secondsLeft s",
                style: TextStyle(
                  color: _secondsLeft == 0 ? const Color(0xFF06b6d4) : Colors.white24,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
            setState(() => _step = _SignUpStep.email);
          },
          child: const Text("Use a different email"),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    final ok = _pwdCtrl.text.length >= 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ScreenTitle("Create a password"),
        const SizedBox(height: 12),
        StatefulBuilder(
          builder: (context, setSB) {
            bool obscure = true;
            return _PasswordField(
              controller: _pwdCtrl,
              focusNode: _pwdFocus,
              onChanged: (_) => setSB(() {}),
              onSubmitted: (_) => _saveAccount(),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: ok ? Colors.greenAccent : Colors.white54),
            const SizedBox(width: 6),
            Text(
              "At least 12 characters",
              style: TextStyle(
                color: ok ? Colors.greenAccent : const Color(0xFF9ca3af),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PrimaryBtn(
          label: "Create account",
          onPressed: _isLoading ? null : _saveAccount,
          loading: _isLoading,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_step) {
      _SignUpStep.email => _buildEmailStep(),
      _SignUpStep.code => _buildCodeStep(),
      _SignUpStep.password => _buildPasswordStep(),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Create Account", style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.6)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // === Styling helpers ===
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF06b6d4)),
      ),
      filled: true,
      fillColor: const Color(0xFF1f2937),
    );
  }
}

// Reusable Title
class _ScreenTitle extends StatelessWidget {
  final String text;
  const _ScreenTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// Primary button
class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _PrimaryBtn({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF06b6d4),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// Password field with show/hide
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: "Password",
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF374151)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF06b6d4)),
        ),
        filled: true,
        fillColor: const Color(0xFF1f2937),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
              color: Colors.white70),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}
