import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';

class SignUpPage extends StatefulWidget {
  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance; // Firestore Instance

  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool isLoading = false;

  Future<void> signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim();

    // 1. Basic Validation
    if (email.isEmpty ||
        password.isEmpty ||
        firstName.isEmpty ||
        username.isEmpty) {
      _showSnackBar("Please fill in all fields", Colors.red);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match", Colors.red);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Create the Auth Account
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      // 2. Try to save to Firestore
      try {
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'username': _usernameController.text.trim(),
          'email': email,
          'createdAt': DateTime.now(),
        });
      } catch (e) {
        debugPrint("Firestore Error: $e");
        // Even if Firestore fails, we might want to tell the user
        // or at least stop the loading state
      }

      await userCredential.user?.sendEmailVerification();

      // Log the user out immediately so they have to log in AFTER verifying
      await _auth.signOut();

      setState(() => isLoading = false);

      if (!mounted) return;

      // Show the pop-up instead of navigating to home
      _showVerificationDialog();
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? 'Signup failed', Colors.red);
    } catch (e) {
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
  final double screenWidth = MediaQuery.of(context).size.width;
  // Determine if we are on a large screen
  final bool isLargeScreen = screenWidth > 600;

  return Scaffold(
    backgroundColor: isLargeScreen ? const Color(0xFFF0F7F9) : Colors.white,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            // Constrain the width of the form on large screens
            constraints: const BoxConstraints(maxWidth: 500),
            margin: EdgeInsets.all(isLargeScreen ? 24 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isLargeScreen ? 20 : 0),
              boxShadow: isLargeScreen
                  ? [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button with Mouse Pointer
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Color(0xFF3F7795),
                    ),
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

                // Organized Form Fields
                _buildResponsiveRow(
                  isLargeScreen,
                  TextField(
                    controller: _firstNameController,
                    decoration: _inputStyle("First Name", Icons.person_outline),
                  ),
                  TextField(
                    controller: _lastNameController,
                    decoration: _inputStyle("Last Name", Icons.person_outline),
                  ),
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

                // Sign Up Button with Mouse Pointer
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: ElevatedButton(
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
                      ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// Helper widget to show fields side-by-side on desktop if desired, 
// or stacked on mobile. For SignUp, stacking is usually cleaner, 
// but we'll use a simple wrapper here for consistency.
Widget _buildResponsiveRow(bool isLarge, Widget left, Widget right) {
  return Column(
    children: [
      left,
      const SizedBox(height: 15),
      right,
    ],
  );
}
}