import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(PetSpectorApp());
}

class PetSpectorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetSpector',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: SplashScreen(), // 👈 Start with SplashScreen directly
    );
  }
}
