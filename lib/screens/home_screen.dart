import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'cam_scan_screen.dart';
import 'mood_detector_screen.dart';
import 'notification_settings_screen.dart';

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
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _isEditingProfile = false;

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
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim();
    
    if (firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your first name."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your username."),
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
      
      final updateData = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'username': username,
        'email': user.email,
      };
      
      if (imageUrl != null) {
        updateData['photoUrl'] = imageUrl;
      }
      
      await _firestore.collection('users').doc(user.uid).set(
        updateData,
        SetOptions(merge: true),
      );
      
      setState(() => _isEditingProfile = false);
      
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

  // Combined stream for scans and mood analyses
  Stream<List<Map<String, dynamic>>> _combinedScansStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    final controller = StreamController<List<Map<String, dynamic>>>();
    QuerySnapshot? lastScansSnapshot;
    QuerySnapshot? lastMoodSnapshot;

    final scansSubscription = _firestore
        .collection('scans')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      lastScansSnapshot = snapshot;
      _emitCombined(controller, lastScansSnapshot, lastMoodSnapshot);
    });

    final moodSubscription = _firestore
        .collection('mood_analysis')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      lastMoodSnapshot = snapshot;
      _emitCombined(controller, lastScansSnapshot, lastMoodSnapshot);
    });

    controller.onCancel = () {
      scansSubscription.cancel();
      moodSubscription.cancel();
    };

    return controller.stream;
  }

  void _emitCombined(
    StreamController<List<Map<String, dynamic>>> controller,
    QuerySnapshot? scansSnapshot,
    QuerySnapshot? moodSnapshot,
  ) {
    if (scansSnapshot == null && moodSnapshot == null) {
      controller.add([]);
      return;
    }

    final allItems = <Map<String, dynamic>>[];

    // Add scans with type marker
    if (scansSnapshot != null) {
      for (var doc in scansSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['_type'] = 'scan';
        data['_id'] = doc.id;
        allItems.add(data);
      }
    }

    // Add mood analyses with type marker
    if (moodSnapshot != null) {
      for (var doc in moodSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['_type'] = 'mood';
        data['_id'] = doc.id;
        allItems.add(data);
      }
    }

    // Sort by timestamp (most recent first)
    allItems.sort((a, b) {
      final aTs = a['timestamp'] as Timestamp?;
      final bTs = b['timestamp'] as Timestamp?;
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });

    controller.add(allItems);
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
    final bool isMood = data['_type'] == 'mood';
    
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
                child: isMood 
                    ? _buildMoodDetailContent(data)
                    : _buildScanDetailContent(data),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanDetailContent(Map<String, dynamic> data) {
    final int accuracyInt = data['accuracy'] ?? 0;
    final double accuracyDouble = accuracyInt / 100.0;

    return Column(
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
                    color: Colors.blueGrey[700],
                  ),
                ),
                Text(
                  "$accuracyInt%",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3F7795),
                  ),
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
    );
  }

  Widget _buildMoodDetailContent(Map<String, dynamic> data) {
    final int confidenceInt = data['confidence'] ?? 0;
    final double confidenceDouble = confidenceInt / 100.0;
    
    // Mood color mapping
    Color moodColor = _getMoodColor(data['mood'] ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- MEDIA SECTION ---
        if (data['mediaUrl'] != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(
              data['mediaUrl'],
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

        // --- MOOD BADGE ---
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: moodColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: moodColor, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mood, color: moodColor, size: 32),
                const SizedBox(width: 12),
                Text(
                  data['mood'] ?? 'Unknown Mood',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: moodColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // --- CONFIDENCE SECTION ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Confidence Level",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            Text(
              "$confidenceInt%",
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3F7795),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: confidenceDouble,
            backgroundColor: const Color(0xFFEEEEEE),
            color: const Color(0xFF3F7795),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 25),

        // --- INFO CARDS ---
        _buildInfoCard(
          title: "Body Language",
          icon: Icons.gesture,
          color: const Color(0xFFE3F2FD),
          iconColor: Colors.blue,
          child: Text(data['bodyLanguage'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Behavior Analysis",
          icon: Icons.psychology,
          color: const Color(0xFFF3E5F5),
          iconColor: Colors.purple,
          child: Text(data['behaviorAnalysis'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Positive Signs",
          icon: Icons.sentiment_very_satisfied,
          color: const Color(0xFFF0F9F1),
          iconColor: Colors.green,
          child: Text(data['positiveSigns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Concerns",
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFFFF4F2),
          iconColor: Colors.redAccent,
          child: Text(data['concerns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          title: "Recommendations",
          icon: Icons.lightbulb_outline_rounded,
          color: const Color(0xFFFFF9E6),
          iconColor: Colors.orange,
          child: Text(data['recommendations'] ?? ""),
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
    );
  }

  Color _getMoodColor(String mood) {
    final moodLower = mood.toLowerCase();
    if (moodLower.contains('happy') || moodLower.contains('playful') || moodLower.contains('excited')) {
      return Colors.green;
    } else if (moodLower.contains('calm') || moodLower.contains('content')) {
      return Colors.blue;
    } else if (moodLower.contains('anxious') || moodLower.contains('stressed') || moodLower.contains('scared')) {
      return Colors.red;
    } else if (moodLower.contains('alert')) {
      return Colors.orange;
    }
    return const Color(0xFF3F7795);
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
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MoodDetectorScreen()),
                ),
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

          // --- Real-time Combined Scans and Mood Analyses List ---
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _combinedScansStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snapshot.data ?? [];

              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text("No scans found in your history.")),
                );
              }

              return ListView.separated(
                key: const PageStorageKey('history_list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = items[index];
                  final bool isMood = data['_type'] == 'mood';
                  final String title = isMood 
                      ? (data['mood'] ?? 'Mood Analysis')
                      : (data['result'] ?? 'Unknown Pet');
                  final Timestamp? ts = data['timestamp'] as Timestamp?;
                  final String? mediaUrl = data['imageUrl'] ?? data['mediaUrl'];
                  final int score = isMood 
                      ? (data['confidence'] ?? 0)
                      : (data['accuracy'] ?? 0);
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
                          child: mediaUrl != null
                              ? Image.network(
                                  mediaUrl,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        width: 50,
                                        height: 50,
                                        color: const Color(0xFFF0F7F9),
                                        child: Icon(
                                          isMood ? Icons.mood : Icons.pets,
                                          color: const Color(0xFF3F7795),
                                        ),
                                      ),
                                )
                              : Container(
                                  width: 50,
                                  height: 50,
                                  color: const Color(0xFFF0F7F9),
                                  child: Icon(
                                    isMood ? Icons.mood : Icons.pets,
                                    color: const Color(0xFF3F7795),
                                  ),
                                ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (score > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF3F7795,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  "$score%",
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF3F7795),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            if (isMood)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  "Mood",
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Text(dateStr),
                          ],
                        ),
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
              if (data == null || (data['firstName'] == null && data['name'] == null)) {
                return _buildProfileForm();
              }
              return _buildProfileDisplay(data);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProfileForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: const Color(0xFFF0F7F9),
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!)
                        : null,
                    child: _imageFile == null
                        ? const Icon(Icons.person, size: 60, color: Color(0xFF3F7795))
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF3F7795),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _firstNameController,
            decoration: InputDecoration(
              labelText: "First Name",
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF3F7795)),
              filled: true,
              fillColor: const Color(0xFFF0F7F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _lastNameController,
            decoration: InputDecoration(
              labelText: "Last Name",
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF3F7795)),
              filled: true,
              fillColor: const Color(0xFFF0F7F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: "Username",
              prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF3F7795)),
              filled: true,
              fillColor: const Color(0xFFF0F7F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 30),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F7795),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text(
                    "Save Profile",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildProfileDisplay(Map<String, dynamic> data) {
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final username = data['username'] ?? '';
    final email = data['email'] ?? '';
    final photoUrl = data['photoUrl'];

    // Load data into controllers when editing
    if (_isEditingProfile && _firstNameController.text.isEmpty) {
      _firstNameController.text = firstName;
      _lastNameController.text = lastName;
      _usernameController.text = username;
    }

    if (_isEditingProfile) {
      return _buildProfileForm();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Stack(
            children: [
              CircleAvatar(
                radius: 70,
                backgroundColor: const Color(0xFFF0F7F9),
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 70, color: Color(0xFF3F7795))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '$firstName $lastName'.trim().isEmpty ? 'No Name' : '$firstName $lastName'.trim(),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '@$username',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 30),
          _buildProfileInfoCard(Icons.email, "Email", email),
          const SizedBox(height: 15),
          _buildProfileInfoCard(Icons.calendar_today, "Member Since", 
              data['createdAt'] != null 
                  ? "${(data['createdAt'] as Timestamp).toDate().day}/${(data['createdAt'] as Timestamp).toDate().month}/${(data['createdAt'] as Timestamp).toDate().year}"
                  : "N/A"),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _isEditingProfile = true;
                  _imageFile = null; // Reset image file
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3F7795),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                "Edit Profile",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3F7795)),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationSettingsScreen(),
                    ),
                  );
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
