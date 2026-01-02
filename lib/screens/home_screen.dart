import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'cam_scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; // 0: Home, 1: Scan, 2: Profile, 3: Settings
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  File? _imageFile;
  bool _isLoading = false;
  final TextEditingController _nameController = TextEditingController();

  // --- Logic Methods ---

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
        final storageRef = FirebaseStorage.instance.ref().child(
          'profiles/${user.uid}/profile.jpg',
        );
        await storageRef.putFile(_imageFile!);
        imageUrl = await storageRef.getDownloadURL();
      }
      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': user.email,
        'photoUrl': imageUrl,
      }, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile saved!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream() {
    final user = _auth.currentUser;
    return user == null
        ? const Stream.empty()
        : _firestore.collection('users').doc(user.uid).snapshots();
  }

  // UI Helper Widget for info blocks in the History Detail Sheet
  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: iconColor.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

void _showHistoryDetail(Map<String, dynamic> data) {
  // Extract accuracy for the progress bar
  final int accuracyInt = data['accuracy'] ?? 0;
  final double accuracyDouble = accuracyInt / 100.0;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            height: 5,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- IMAGE SECTION ---
                  if (data['imageUrl'] != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        data['imageUrl'],
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, size: 50),
                            ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // --- BREED & DESCRIPTION ---
                  Text(
                    data['result'] ?? 'Unknown Breed',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (data['description'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        data['description'],
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 20),

                  // --- ACCURACY SECTION ---
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Identification Match",
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey[700]),
                          ),
                          Text(
                            "$accuracyInt%",
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3F7795)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: accuracyDouble,
                          backgroundColor: const Color(0xFFEEEEEE),
                          color: const Color(0xFF3F7795),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 25),

                  // --- INFO CARDS ---
                  _buildInfoCard(
                    title: "Common Allergies",
                    icon: Icons.warning_amber_rounded,
                    color: const Color(0xFFFFF4F2),
                    iconColor: Colors.redAccent,
                    child: Text(
                      data['allergies'] ?? "No allergy data saved.",
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildInfoCard(
                    title: "Care Tips",
                    icon: Icons.lightbulb_outline_rounded,
                    color: const Color(0xFFF0F9F1),
                    iconColor: Colors.green,
                    child: Text(data['care'] ?? "No care tips saved."),
                  ),
                  const SizedBox(height: 30),

                  // --- CLOSE BUTTON ---
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3F7795),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        "Close",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildHomeTab() {
  return SingleChildScrollView(
    // PageStorageKey helps the ScrollView remember its position when switching tabs
    key: const PageStorageKey('home_scroll_view'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header Section ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _profileStream(),
              builder: (context, snapshot) {
                String displayName = "Pet Lover";
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data();
                  displayName = data?['firstName'] ?? "Pet Lover";
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, $displayName",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3142),
                      ),
                    ),
                    const Text(
                      "Ready to check your pet today?",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
            GestureDetector(
              onTap: () => setState(() => _selectedIndex = 3),
              child: const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFFF0F7F9),
                child: Icon(Icons.settings, color: Color(0xFF3F7795)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // --- Quick Actions Grid ---
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.5,
          children: [
            _buildActionCard(
              Icons.camera_alt_rounded,
              "Breed Detector",
               const Color(0xFF3F7795),
              () => setState(() => _selectedIndex = 1),
            ),
            _buildActionCard(
              Icons.video_collection,
              "Mood Detector",
              const Color(0xFF3F7795),
              () => setState(() => _selectedIndex = 1),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // --- Recent Scans Header ---
        const Text(
          "Recent Scans",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        // --- Real-time Firestore Scans List ---
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('scans')
              .where(
                'userId',
                isEqualTo: FirebaseAuth.instance.currentUser?.uid,
              )
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text("Error: ${snapshot.error}"));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No scans found in your history.")),
              );
            }

            return ListView.separated(
              key: const PageStorageKey('history_list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final String breed = data['result'] ?? 'Unknown Pet';
                final Timestamp? ts = data['timestamp'] as Timestamp?;
                final String? imageUrl = data['imageUrl'];
                final int accuracy = data['accuracy'] ?? 0;
                final String dateStr = ts != null
                    ? "${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}"
                    : "Processing...";

                return Card(
                  color: Colors.white,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _showHistoryDetail(data),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                color: const Color(0xFFF0F7F9),
                                child: const Icon(Icons.pets, color: Color(0xFF3F7795)),
                              ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              breed,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (accuracy > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3F7795).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                "$accuracy%",
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF3F7795),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(dateStr),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    ),
                  ),
                );
              },
            );
          },
        ),
        // Spacer at the bottom to ensure bottom items aren't hidden by the Nav Bar
        const SizedBox(height: 40),
      ],
    ),
  );
}

  Widget _buildActionCard(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCamScanTab() {
    return Stack(
      children: [
        const CamScanScreen(),
        Positioned(
          top: 10,
          left: 10,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => setState(() => _selectedIndex = 0),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    return Column(
      children: [
        // Top Back Bar for Profile
        ListTile(
          leading: const Icon(Icons.arrow_back),
          title: const Text(
            "My Profile",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onTap: () => setState(() => _selectedIndex = 0),
        ),
        Expanded(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _profileStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              final data = snapshot.data?.data();
              if (data == null || data['name'] == null) {
                return _buildProfileForm();
              }
              return _buildProfileDisplay(data);
            },
          ),
        ),
      ],
    );
  }

  // ... (Keep your existing _buildProfileForm and _buildProfileDisplay logic here)
  // For brevity, using a placeholder for Display/Form logic below
  Widget _buildProfileForm() {
    return const Center(child: Text("Profile Form Here"));
  }

  Widget _buildProfileDisplay(Map<String, dynamic> data) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: NetworkImage(data['photoUrl'] ?? ''),
          ),
          Text(
            data['name'],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          ElevatedButton(
            onPressed: () => setState(() => _selectedIndex = 0),
            child: const Text("Back to Dashboard"),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Back Button
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedIndex = 0),
              ),
              const Text(
                "Settings",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Settings Options
        Expanded(
          child: ListView(
            children: [
              _buildSettingsSectionTitle("Account"),
              _buildSettingsTile(
                icon: Icons.person_outline,
                title: "Edit Profile",
                subtitle: "Change your name and profile picture",
                onTap: () =>
                    setState(() => _selectedIndex = 2), // Go to Profile Tab
              ),

              const Divider(indent: 70),

              _buildSettingsSectionTitle("System"),
              _buildSettingsTile(
                icon: Icons.notifications_none,
                title: "Notifications",
                subtitle: "Manage your alerts",
                onTap: () {
                  /* Future Feature */
                },
              ),

              const Divider(indent: 70),

              _buildSettingsSectionTitle("Danger Zone"),
              _buildSettingsTile(
                icon: Icons.logout,
                title: "Logout",
                subtitle: "Sign out of your account",
                color: Colors.redAccent,
                onTap: () async {
                  await _auth.signOut();
                  if (mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper for Section Titles
  Widget _buildSettingsSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // Helper for List Tiles
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = const Color(0xFF3F7795),
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildHomeTab(),
      _buildCamScanTab(),
      _buildProfileTab(),
      _buildSettingsTab(),
    ];

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(body: SafeArea(child: tabs[_selectedIndex])),
    );
  }
}
