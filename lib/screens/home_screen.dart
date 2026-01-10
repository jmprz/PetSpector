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
import 'package:video_player/video_player.dart'; // Add this line
import 'package:fl_chart/fl_chart.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class FullscreenVideoPlayer extends StatefulWidget {
  final String url;
  const FullscreenVideoPlayer({super.key, required this.url});

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) => setState(() {
            _controller.play();
            _controller.setLooping(true);
          }));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
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

  String _currentFilter = 'All'; // Options: 'All', 'Breed', 'Mood'

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

      void _handleLogout(BuildContext context) async {
  // Show a confirmation dialog
  bool? confirm = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Logout"),
      content: const Text("Are you sure you want to sign out?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        TextButton(
          onPressed: () => Navigator.pop(context, true), 
          child: const Text("Logout", style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    await FirebaseAuth.instance.signOut();
    // Navigate to login and remove all previous screens from the stack
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
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

Widget _buildConfidenceGraph(int percentage, Color color) {
  return SizedBox(
    height: 150,
    child: Stack(
      children: [
        PieChart(
          PieChartData(
            startDegreeOffset: 270,
            sectionsSpace: 0,
            centerSpaceRadius: 50,
            sections: [
              PieChartSectionData(
                color: color,
                value: percentage.toDouble(),
                showTitle: false,
                radius: 12,
              ),
              PieChartSectionData(
                color: color.withOpacity(0.1),
                value: (100 - percentage).toDouble(),
                showTitle: false,
                radius: 12,
              ),
            ],
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "$percentage%",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Text(
                "Match",
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildBreedBarChart(List<Map<String, dynamic>> matches) {
  return Column(
    children: matches.map((m) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m['breed'], style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: m['confidence'] / 100,
                minHeight: 10,
                color: const Color(0xFF3F7795),
                backgroundColor: Colors.grey[200],
              ),
            ),
          ],
        ),
      );
    }).toList(),
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
const SizedBox(height: 10),
Center(
  child: _buildConfidenceGraph(
    accuracyInt, 
    const Color(0xFF3F7795),
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
 // --- MEDIA SECTION ---
if (data['mediaUrl'] != null) ...[
  GestureDetector(
    onTap: () {
      if (data['mediaUrl'].contains('.mp4')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullscreenVideoPlayer(url: data['mediaUrl']),
          ),
        );
      }
    },
    child: Container(
      height: 250, // Slightly shorter to save space
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        image: !data['mediaUrl'].contains('.mp4') 
            ? DecorationImage(image: NetworkImage(data['mediaUrl']), fit: BoxFit.cover)
            : null,
      ),
      child: data['mediaUrl'].contains('.mp4')
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline, color: Colors.white, size: 80),
                  SizedBox(height: 10),
                  Text("Tap to Play Video", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : null,
    ),
  ),
  const SizedBox(height: 20),
],

  // --- MOOD BADGE ---
Center(
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    // Added a constraint to ensure the badge doesn't try to be wider than the screen
    constraints: const BoxConstraints(maxWidth: 300), 
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
        // Wrap the text in Flexible to prevent the 320px overflow error
        Flexible(
          child: Text(
            data['mood'] ?? 'Unknown Mood',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: moodColor,
            ),
            overflow: TextOverflow.ellipsis, // Adds "..." if the text is too long
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

Widget _buildHistoryCard(Map<String, dynamic> data) {
  final bool isMood = data['_type'] == 'mood';
  final String title = isMood ? (data['mood'] ?? 'Mood Analysis') : (data['result'] ?? 'Unknown Pet');
  final int score = isMood ? (data['confidence'] ?? 0) : (data['accuracy'] ?? 0);
  final Timestamp? ts = data['timestamp'] as Timestamp?;
  final String dateStr = ts != null ? _formatTimestamp(ts) : "Just now";

  // --- SPECIFIC COLOR CONFIGURATION ---
  // Primary Blue is used elsewhere, so we use unique colors for the history categories
  final Color breedColor = Colors.orange.shade800; // Distinct color for Breed Scans
  final Color moodColor = const Color(0xFF6C63FF); // Distinct color for Mood Analysis
  
  final Color themeColor = isMood ? moodColor : breedColor;
  final IconData themeIcon = isMood ? Icons.videocam_rounded : Icons.pets_rounded;

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 15,
          offset: const Offset(0, 5),
        )
      ],
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: themeColor.withOpacity(0.12), // Soft background of the specific color
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(themeIcon, color: themeColor, size: 26),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold, 
          fontSize: 16, 
          color: Color(0xFF2D3142),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "$score%",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: themeColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
        ],
      ),
      onTap: () => _showHistoryDetail(data),
    ),
  );
}

// Simple Date Formatter
String _formatTimestamp(Timestamp ts) {
  DateTime dt = ts.toDate();
  return "${dt.day}/${dt.month}/${dt.year}";
}

Widget _buildCustomHeader() {
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _profileStream(),
    builder: (context, snapshot) {
      String displayName = "Pet Lover";
      if (snapshot.hasData && snapshot.data!.exists) {
        final data = snapshot.data!.data();
        displayName = data?['firstName'] ?? "Pet Lover";
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
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
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedIndex = 2), // Navigate to Profile
            child: const CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xFFF0F7F9),
              child: Icon(Icons.person, color: Color(0xFF3F7795)),
            ),
          ),
        ],
      );
    },
  );
}

 Widget _buildHomeTab() {
  return SingleChildScrollView(
    key: const PageStorageKey('home_scroll_view'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header Section ---
        _buildCustomHeader(),

        const SizedBox(height: 25),

        // --- Quick Actions Grid ---
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 15,
          mainAxisSpacing: 15,
          childAspectRatio: 1.4,
          children: [
            _buildActionCard(
              Icons.center_focus_strong,
              "Breed Detector",
              "Identify breeds",
              Colors.orange.shade800,
              () => setState(() => _selectedIndex = 1),
            ),
            _buildActionCard(
              Icons.insights,
              "Mood Detector",
              "Analyze behavior",
              const Color(0xFF6C63FF), // Distinct color for Mood
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MoodDetectorScreen()),
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // --- Recent Scans Header & Filter ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Recent Activity",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
            ),
          ],
        ),
        
        // --- Filter Chips ---
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', 'Breed', 'Mood'].map((filter) {
              bool isSelected = _currentFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (bool value) {
                    setState(() => _currentFilter = filter);
                  },
                  selectedColor: const Color(0xFF3F7795).withOpacity(0.2),
                  checkmarkColor: const Color(0xFF3F7795),
                  labelStyle: TextStyle(
                    color: isSelected ? const Color(0xFF3F7795) : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 15),

        // --- Real-time Combined List ---
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _combinedScansStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // FILTER LOGIC
            final allItems = snapshot.data ?? [];
            final items = allItems.where((item) {
              if (_currentFilter == 'All') return true;
              if (_currentFilter == 'Mood') return item['_type'] == 'mood';
              if (_currentFilter == 'Breed') return item['_type'] != 'mood';
              return true;
            }).toList();

            if (items.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildHistoryCard(items[index]),
            );
          },
        ),
        const SizedBox(height: 40),
      ],
    ),
  );
}

Widget _buildEmptyState() {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.history_rounded, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            "No ${_currentFilter == 'All' ? 'activity' : _currentFilter.toLowerCase() + 's'} found",
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildActionCard(
    IconData icon,
    String label,
    String subtitle, 
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
        _buildProfileInfoCard(
          Icons.calendar_today, 
          "Member Since", 
          data['createdAt'] != null 
              ? "${(data['createdAt'] as Timestamp).toDate().day}/${(data['createdAt'] as Timestamp).toDate().month}/${(data['createdAt'] as Timestamp).toDate().year}"
              : "N/A"
        ),
        
        const SizedBox(height: 30),

        // --- BUTTONS SECTION ---
        Column(
          children: [
            // Edit Profile Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _isEditingProfile = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F7795),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text(
                  "Edit Profile",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12), // Space between buttons

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
          ],
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
