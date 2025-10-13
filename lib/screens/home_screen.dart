import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'cam_scan_screen.dart'; // Import the new camera screen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Set initial index to 1 (Scan/Camera tab) as it's the main feature
  int _selectedIndex = 1; 
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  File? _imageFile;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your name."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profiles/${user.uid}/profile.jpg');
        await storageRef.putFile(_imageFile!);
        imageUrl = await storageRef.getDownloadURL();
      }

      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'photoUrl': imageUrl,
      }, SetOptions(merge: true)); // Use merge to avoid overwriting other fields

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving profile: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Changed to use StreamBuilder for real-time profile updates
  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream() {
    final user = _auth.currentUser;
    if (user == null) {
      // Return an empty stream if no user is logged in
      return const Stream.empty();
    }
    return _firestore.collection('users').doc(user.uid).snapshots();
  }

  // --- Tab Builders ---

  Widget _buildHomeTab() {
    final user = _auth.currentUser;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Welcome ${user?.email ?? 'User'} 👋",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "Tap 'Scan' below to analyze your pet!",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // NEW: Tab for the camera functionality
  Widget _buildCamScanTab() {
    // The CamScanScreen manages its own state for camera initialization
    return const CamScanScreen(); 
  }

  // Existing Profile Tab logic, updated to use StreamBuilder
  Widget _buildProfileTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.data();

        // 1. Logic to show the profile creation form if no profile data exists
        if (data == null || data.isEmpty || data['name'] == null) {
          // Initialize controller with current email if available
          _nameController.text = data?['name'] ?? '';
          
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text(
                    "Create Your Profile",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[300],
                      backgroundImage:
                          _imageFile != null ? FileImage(_imageFile!) : null,
                      child: _imageFile == null
                          ? const Icon(Icons.camera_alt, size: 40)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "Full Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 25),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: const Color(0xFF3F7795),
                          ),
                          child: const Text("Save Profile"),
                        ),
                ],
              ),
            ),
          );
        } else {
          // 2. Logic to show the saved profile
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data['photoUrl'] != null)
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(data['photoUrl']),
                  )
                else
                   CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[300],
                    child: Text(data['name'][0].toUpperCase(), style: const TextStyle(fontSize: 40)),
                  ),
                const SizedBox(height: 15),
                Text(
                  data['name'] ?? 'User',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data['email'] ?? 'No email',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    // Go back to the login screen using the navigation context
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSettingsTab() {
    return const Center(
      child: Text("Settings Coming Soon ⚙️"),
    );
  }

  // --- Main Build Method ---

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildHomeTab(),
      _buildCamScanTab(), // Index 1: The new camera screen
      _buildProfileTab(),
      _buildSettingsTab(),
    ];

    // Determine the title based on the selected index
    String screenTitle = '';
    switch (_selectedIndex) {
      case 0:
        screenTitle = 'PetSpector Dashboard';
        break;
      case 1:
        screenTitle = 'Scan Pet Condition';
        break;
      case 2:
        screenTitle = 'My Profile';
        break;
      case 3:
        screenTitle = 'Settings';
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
        backgroundColor: const Color(0xFF3F7795), // Using your app's primary color
        elevation: 0,
      ),
      body: tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          // Ensure that the Profile tab redraws immediately if necessary
          if (_selectedIndex == 2 && index != 2) {
            // If leaving the profile tab, ensure state is reset for text controller
             _nameController.clear();
          }
          setState(() => _selectedIndex = index);
        },
        selectedItemColor: const Color(0xFF3F7795),
        unselectedItemColor: Colors.grey, 
        type: BottomNavigationBarType.fixed, // Keeps all 4 tabs visible and sized evenly
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Scan'), // Index 1
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
