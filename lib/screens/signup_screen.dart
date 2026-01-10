import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'dart:io';

class SignUpPage extends StatefulWidget {
  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
 late final FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  bool isFirebaseSupported = false; 
  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Only initialize if supported, otherwise use dummy logic
    if (!Platform.isLinux && isFirebaseSupported) {
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
    }
  }

 Future<void> signUp() async {
    // 1. Linux Simulation Check (Keep this at the very top)
    if (Platform.isLinux || !isFirebaseSupported) {
      debugPrint("🚀 Linux Mode: Simulating successful signup...");
      setState(() => isLoading = true);
      await Future.delayed(const Duration(seconds: 1)); 
      if (!mounted) return;
      _showVerificationDialog(); // Test your dialog on Linux!
      setState(() => isLoading = false);
      return;
    }

    // 2. Data Preparation
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // 3. Validation
    if (email.isEmpty || password.isEmpty || _usernameController.text.isEmpty) {
      _showSnackBar("Please fill in all fields", Colors.red);
      return;
    }
    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match", Colors.red);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 4. Create Auth Account
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email, 
        password: password
      );

      // 5. Save to Firestore 
      // TIP: Do this BEFORE signing out, while the user still has permission to write!
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'email': email,
        'createdAt': FieldValue.serverTimestamp(), // Better than DateTime.now()
      });

      // 6. Send Verification Email
      await userCredential.user?.sendEmailVerification();

      // 7. Sign Out
      // IMPORTANT: If you have an Auth Listener in main.dart, 
      // this might trigger a navigation change.
      await _auth.signOut();

      if (!mounted) return;
      _showVerificationDialog();

    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? 'Signup failed', Colors.red);
    } catch (e) {
      debugPrint("Unexpected Error: $e");
      _showSnackBar("An unexpected error occurred", Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap the button
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Verify Your Email",
            style: TextStyle(
              color: Color(0xFF3F7795),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "A verification link has been sent to your email. "
            "Please check your inbox (and spam folder) to verify your account before logging in.",
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.pushReplacementNamed(
                  context,
                  '/login',
                ); // Go to login
              },
              child: const Text(
                "OK",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        );
      },
    );
  }

  // Reusable TextField Decoration to keep code clean
  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF3F7795)),
      filled: true,
      fillColor: const Color(0xFFF0F7F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Color(0xFF3F7795),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3F7795),
                ),
              ),
              const Text(
                "Fill in your details to get started",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // First & Last Name Row
              const SizedBox(height: 15),
              TextField(
                controller: _firstNameController,
                decoration: _inputStyle("First Name", Icons.person_outline),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _lastNameController,
                decoration: _inputStyle("Last Name", Icons.person_outline),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _usernameController,
                decoration: _inputStyle("Username", Icons.alternate_email),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _emailController,
                decoration: _inputStyle("Email", Icons.email_outlined),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _inputStyle("Password", Icons.lock_outline),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: _inputStyle("Confirm Password", Icons.lock_reset),
              ),

              const SizedBox(height: 30),

              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: signUp,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: const Color(0xFF3F7795),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
