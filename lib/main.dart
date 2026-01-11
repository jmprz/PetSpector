import 'package:flutter/material.dart';
import 'dart:async';
import 'screens/signup_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// Retaining the prefix 'fb_auth' to prevent the conflict with Supabase's 'User' class
import 'package:firebase_auth/firebase_auth.dart' as fb_auth; 
import 'screens/home_screen.dart';
import 'package:camera/camera.dart'; 
import 'screens/cam_scan_screen.dart'; // NEW: Import the camera screen
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Global variable to store the list of available cameras
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load .env file if it exists
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found. Please create .env file with GEMINI_API_KEY: $e");
    // Continue execution - breed_detector and mood_detector will handle missing API key
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  
  // Initialize cameras (needed for CamScanScreen)
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error getting available cameras: $e');
    // Initialize to empty list on error to prevent runtime crash
    cameras = [];
  }

  runApp(const PetSpectorApp());
}

class PetSpectorApp extends StatelessWidget {
  const PetSpectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetSpector',
      theme: ThemeData(
        primaryColor: const Color(0xFF3F7795), // theme color
        fontFamily: 'Poppins', // font for the app
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F7795),
        ).copyWith(
          // Ensure primary color is used across the app
          primary: const Color(0xFF3F7795),
        ),
      ),
      debugShowCheckedModeBanner: false,
      // Use the prefixed User object (fb_auth.User) to check authentication state
      home: StreamBuilder<fb_auth.User?>( 
        stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Show splash screen while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          // If user is logged in, go to home screen, otherwise go to login
          if (snapshot.hasData && snapshot.data != null) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/signup': (context) => SignUpPage(),
        '/scan': (context) => const CamScanScreen(), // NEW ROUTE
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    // This splash screen now acts as the loading screen while checking Firebase state
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            // NOTE: Ensure 'assets/images/ps_icon.png' exists in your assets folder
            Image.asset(
              'assets/images/ps_icon.png',
              height: 120,
            ),
            const SizedBox(height: 20),
            // App name
            Text(
              "PetSpector",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            // Tagline
            Text(
              "Smarter Care for Smarter Owners",
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              color: Color(0xFF3F7795),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = fb_auth.FirebaseAuth.instance; 
  
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _loginWithEmail() async {
    setState(() => _isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;

      // Check for email verification, and allow login to proceed if verified
      if (user != null && user.emailVerified) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // If not verified, sign out and prompt user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please verify your email before logging in.'),
            backgroundColor: Colors.red,
          ),
        );
        await _auth.signOut();
      }
    } on fb_auth.FirebaseAuthException catch (e) { // Use prefixed FirebaseAuthException
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        default:
          errorMessage = 'Login failed. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your email to reset password."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password reset email sent! Check your inbox."),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to send reset email. Try again."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


// 1. Helper method (Removed @override)
Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required double scale,
  bool isPassword = false,
}) {
  return TextField(
    controller: controller,
    obscureText: isPassword ? _obscurePassword : false,
    style: TextStyle(fontSize: 16 * scale),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 14 * scale),
      prefixIcon: Icon(icon, color: const Color(0xFF3F7795), size: 22 * scale),
      filled: true,
      fillColor: const Color(0xFFF0F7F9),
      contentPadding: EdgeInsets.symmetric(vertical: 18 * scale, horizontal: 15 * scale),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      suffixIcon: isPassword 
          ? IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 20 * scale,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) 
          : null,
    ),
  );
}

// 2. Main Build Method
@override
Widget build(BuildContext context) {
  final double screenWidth = MediaQuery.of(context).size.width;
  // Scale text and icons slightly on larger screens
  final double scaleFactor = screenWidth > 600 ? 1.15 : 1.0;

  return Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: Container(
          // Limit form width to 450px for a professional Web look
          constraints: const BoxConstraints(maxWidth: 450), 
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo and Branding
                Image.asset('assets/images/ps_icon.png', height: 100 * scaleFactor),
                SizedBox(height: 20 * scaleFactor),
                Text(
                  "PetSpector",
                  style: TextStyle(
                    fontSize: 32 * scaleFactor, 
                    fontWeight: FontWeight.bold, 
                    color: const Color(0xFF3F7795),
                  ),
                ),
                Text(
                  "Login to your account", 
                  style: TextStyle(color: Colors.grey, fontSize: 14 * scaleFactor),
                ),
                SizedBox(height: 40 * scaleFactor),

                // Styled TextFields
                _buildTextField(
                  controller: _emailController,
                  label: "Email",
                  icon: Icons.email_outlined,
                  scale: scaleFactor,
                ),
                SizedBox(height: 15 * scaleFactor),
                _buildTextField(
                  controller: _passwordController,
                  label: "Password",
                  icon: Icons.lock_outline,
                  isPassword: true,
                  scale: scaleFactor,
                ),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _resetPassword,
                    child: Text(
                      "Forgot Password?", 
                      style: TextStyle(
                        color: const Color(0xFF3F7795), 
                        fontWeight: FontWeight.w600,
                        fontSize: 14 * scaleFactor,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20 * scaleFactor),

                // Action Buttons
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _loginWithEmail,
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 55 * scaleFactor),
                          backgroundColor: const Color(0xFF3F7795),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: Text(
                          "Login", 
                          style: TextStyle(fontSize: 18 * scaleFactor, fontWeight: FontWeight.bold),
                        ),
                      ),

                SizedBox(height: 20 * scaleFactor),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(fontSize: 14 * scaleFactor),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/signup'),
                      child: Text(
                        "Sign Up", 
                        style: TextStyle(
                          color: const Color(0xFF3F7795), 
                          fontWeight: FontWeight.bold,
                          fontSize: 14 * scaleFactor,
                        ),
                      ),
                    ),
                  ],
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