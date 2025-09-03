import 'package:flutter/material.dart';
import 'home.dart';
import 'forgot_password.dart';
import 'sign_up.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Prefill for dev, but still editable
  final TextEditingController _emailController =
  TextEditingController(text: "test@email.com");
  final TextEditingController _passwordController =
  TextEditingController(text: "Password123");

  Future<void> login(String email, String password) async {
    // Dev-only hardcoded auth
    if (email == "test@email.com" && password == "Password123") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      showAlert("Invalid credentials",
          "Use test@email.com and Password123 for now.");
    }
  }

  void handleAuthAction() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showAlert("Missing info", "Please enter your email and password.");
      return;
    }

    try {
      await login(email, password);
    } catch (e) {
      showAlert("Auth Error", e.toString());
    }
  }

  void showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                "RotalaLink", // renamed from AquaSpec
                style: TextStyle(
                  fontSize: 40,
                  color: Color(0xFF06b6d4),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Email (editable) with gray placeholder
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                decoration: inputDecoration("Username or email"),
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: inputDecoration("Password"),
              ),
              const SizedBox(height: 16),

              // Forgot password -> page
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text(
                    "Forgot password?",
                    style: TextStyle(
                      color: Color(0xFF06b6d4),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Log in
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06b6d4),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: handleAuthAction,
                child: const Text(
                  "Log In",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),

              // Sign up -> page
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(color: Color(0xFF9ca3af), fontSize: 14),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignUpPage(),
                        ),
                      );
                    },
                    child: const Text(
                      "Sign Up",
                      style: TextStyle(
                        color: Color(0xFF06b6d4),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF999999)), // gray placeholder
      filled: true,
      fillColor: const Color(0xFF1f2937),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
    );
  }
}
