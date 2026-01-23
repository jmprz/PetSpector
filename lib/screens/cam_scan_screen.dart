import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../utils/breed_detector.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

class CamScanScreen extends StatefulWidget {
  const CamScanScreen({super.key});

  @override
  State<CamScanScreen> createState() => _CamScanScreenState();
}

class _CamScanScreenState extends State<CamScanScreen> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;

  final BreedDetector _breedDetector = BreedDetector();
  int _selectedCameraIndex = 0;

  // Change 1: Store XFile instead of File for broad compatibility
  XFile? _currentXFile;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedCameraIndex = _findBackCamera();
    _initializeCamera(_selectedCameraIndex);
  }

  int _findBackCamera() {
    for (int i = 0; i < cameras.length; i++) {
      if (cameras[i].lensDirection == CameraLensDirection.back) {
        return i;
      }
    }
    return 0; 
  }

  Future<void> _initializeCamera(int index) async {
    if (cameras.isEmpty) return;

    // IMPORTANT FOR WEB: Dispose the old controller before creating a new one
    // This prevents the "Camera already in use" error on Android/iOS
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      cameras[index],
      ResolutionPreset.medium, // 'high' can sometimes cause lag/crashes on mobile web
      enableAudio: false,
    );

    _initializeControllerFuture = _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _toggleCamera() {
    if (cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    _initializeCamera(_selectedCameraIndex);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // --- CORE LOGIC: PROCESSING & SAVING ---

  Future<void> _processImage(XFile xFile) async {
    setState(() {
      _isProcessing = true;
      _currentXFile = xFile; // Store it for the UI
    });

    try {
      final Uint8List bytes = await xFile.readAsBytes();

      // Fix for Error 1: Handle prediction based on platform
      // If BreedDetector expects a File, it won't work on Web.
      // Ensure BreedDetector.predict is updated to handle XFile or Bytes.
      final Map<String, dynamic> result = await _breedDetector.predict(xFile);

      if (result['status'] != 'error') {
        await _saveScanToHistory(result, xFile, bytes);
      }

      if (mounted) {
        // Fix for Error 2: Pass xFile to the sheet
        _showResultBottomSheet(result, xFile);
      }
    } catch (e) {
      debugPrint("Processing Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveScanToHistory(
    Map<String, dynamic> result,
    XFile xFile,
    Uint8List bytes,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
  // 2. Fetch the extra profile info from your 'users' collection
  final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final userData = userDoc.data();

    try {
      String fileName =
          'pet_uploads/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      // IMPORTANT: Use putData for Web compatibility
      UploadTask uploadTask = FirebaseStorage.instance
          .ref()
          .child(fileName)
          .putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

      TaskSnapshot snapshot = await uploadTask;
      String imageUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('scans').add({
        'userId': user.uid,
        'result': result['breed'],
        'accuracy': result['accuracy'],
        'description': result['description'],
        'allergies': result['allergies'],
        'care': result['care'],
        'imageUrl': imageUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'matches': result['matches'] ?? [],
        'type': result['type'] ?? 'Unknown',
        '_type': 'breed',
        'userEmail': user.email, // Storing email directly in the scan
        'firstName': userData?['firstName'] ?? 'Guest', // Storing name directly
        'lastName': userData?['lastName'] ?? '',
      });
    } catch (e) {
      debugPrint("❌ Failed to save history: $e");
    }
  }
  }

  // --- UI: BOTTOM SHEETS & CARDS ---

  void _showResultBottomSheet(Map<String, dynamic> data, XFile xFile) {
    final bool isError = data['status'] == 'error';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * (isError ? 0.45 : 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // ... (Drag handle container) ...
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: isError
                    ? _buildErrorView(data)
                    : _buildSuccessView(data, xFile), // Fix: Pass xFile here
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView(Map<String, dynamic> data, XFile xFile) {
    // 1. Setup Data and Variables
    final int accuracyInt = data['accuracy'] ?? 0;

    // Extract matches or create default from top result
    List<dynamic> matches =
        data['matches'] ??
        [
          {
            'breed': data['breed'],
            'percentage': data['accuracy'],
            'color': '#3F7795',
          },
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Captured Image Preview
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: kIsWeb
                ? Image.network(
                    xFile.path,
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(xFile.path),
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
          ),
        ),

        // Breed Title and Type
        Text(
          data['breed'] ?? 'Unknown Breed',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        Text(
          (data['type'] ?? 'Pet').toString().toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[300],
          ),
        ),

        if (data['description'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              data['description'],
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
                height: 1.4, // Improves readability
              ),
            ),
          ),

        const SizedBox(height: 30),

        // 2. DONUT CHART (PieChart with Center Text)
        Center(
          child: SizedBox(
            height: 200,
            child: Stack(
              // Wrap in a Stack to layer text on top
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    sections: matches.map((m) {
                      final colorStr = (m['color'] as String).replaceFirst(
                        '#',
                        '0xFF',
                      );
                      return PieChartSectionData(
                        color: Color(int.parse(colorStr)),
                        value: (m['percentage'] as num).toDouble(),
                        title: '',
                        radius: 35,
                      );
                    }).toList(),
                  ),
                ),
                // The Center Text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$accuracyInt%", // Your accuracy variable
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3F7795),
                      ),
                    ),
                    Text(
                      "Match",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 30),

        // 3. BREED ANALYSIS LIST
        const Text(
          "Breed Analysis",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // The match cards
        ...matches.map((m) => _buildBreedMatchTile(m)),

        const SizedBox(height: 25),

        // 4. INFORMATION CARDS
        _buildInfoCard(
          "Common Allergies",
          Icons.warning_amber_rounded,
          const Color(0xFFFFF4F2),
          Colors.redAccent,
          Text(data['allergies'] ?? "No data available."),
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          "Care Tips",
          Icons.lightbulb_outline_rounded,
          const Color(0xFFF0F9F1),
          Colors.green,
          Text(data['care'] ?? "No data available."),
        ),

        const SizedBox(height: 30),

        // Done Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              backgroundColor: const Color(0xFF3F7795),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Done",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(Map<String, dynamic> data) {
    return Column(
      children: [
        const Icon(
          Icons.nearby_error_outlined,
          color: Colors.orangeAccent,
          size: 70,
        ),
        const Text(
          "Invalid Selection",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          data['care'] ?? "Not a supported pet.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Got it"),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    String title,
    IconData icon,
    Color bg,
    Color ic,
    Widget child,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: ic),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: ic),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // --- ACTIONS ---

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    final XFile image = await _cameraController!.takePicture();
    await _processImage(image); // Pass XFile directly
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) await _processImage(image); // Pass XFile directly
  }

  void _showHelpModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "Scanning Guide",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildHelpRow(
              Icons.light_mode_outlined,
              "Good Lighting",
              "Ensure your pet is in a well-lit area for better accuracy.",
            ),
            _buildHelpRow(
              Icons.center_focus_weak,
              "Center Your Pet",
              "Keep the pet within the corner brackets for a clear scan.",
            ),
            _buildHelpRow(
              Icons.timer_outlined,
              "Stay Still",
              "Hold your phone steady while taking the photo.",
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F7795),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Got it!",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF3F7795).withOpacity(0.1),
            child: Icon(icon, color: const Color(0xFF3F7795), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scaleFactor = screenWidth > 600 ? 1.2 : 1.0;

    return Scaffold(
      backgroundColor: Colors
          .transparent, // Pure black for the areas outside the camera feed
      body: Center(
        child: Container(
          // Constrains the camera and UI to a central column on large screens
          constraints: const BoxConstraints(maxWidth: 1200),
          color: Colors.black,
          child: Stack(
            children: [
              // 1. Camera Preview
              Positioned.fill(
                child: FutureBuilder(
                  future: _initializeControllerFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        _cameraController != null) {
                      return CameraPreview(_cameraController!);
                    }
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                ),
              ),

              // 2. Custom Header (Replaces AppBar)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 15,
                right: 15,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button with circular transparent background
                    _buildCircleAction(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () => Navigator.pop(context),
                      scale: 0.85, // Slightly smaller than bottom buttons
                    ),

                    // Screen Title
                    const Text(
                      "Breed Detector",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                      ),
                    ),

                    // Info Button with circular transparent background
                    _buildCircleAction(
                      icon: Icons.info_outline,
                      onTap: _showHelpModal,
                      scale: 0.85,
                    ),
                  ],
                ),
              ),

              // 3. Stylized Scanning Frame
              Center(
                child: SizedBox(
                  width: 300 * scaleFactor,
                  height: 300 * scaleFactor,
                  child: Stack(
                    children: [
                      _buildCorner(top: true, left: true, scale: scaleFactor),
                      _buildCorner(top: true, left: false, scale: scaleFactor),
                      _buildCorner(top: false, left: true, scale: scaleFactor),
                      _buildCorner(top: false, left: false, scale: scaleFactor),
                    ],
                  ),
                ),
              ),

              if (_isProcessing)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),

              // 4. Bottom Controls
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircleAction(
                      icon: Icons.photo_library_outlined,
                      onTap: _pickImageFromGallery,
                      scale: scaleFactor,
                    ),

                    // Main Shutter Button
                    GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        height: 80 * scaleFactor,
                        width: 80 * scaleFactor,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),

                    _buildCircleAction(
                      icon: Icons.flip_camera_ios_outlined,
                      onTap: _toggleCamera,
                      scale: scaleFactor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorner({
    required bool top,
    required bool left,
    required double scale,
  }) {
    final double cornerSize =
        25.0 * scale; // Slightly smaller for a sharper look
    const double thickness = 4.0;
    const Color cornerColor = Colors.white;

    return Positioned(
      top: top ? 0 : null,
      bottom: !top ? 0 : null,
      left: left ? 0 : null,
      right: !left ? 0 : null,
      child: Container(
        width: cornerSize,
        height: cornerSize,
        decoration: BoxDecoration(
          border: Border(
            top: top
                ? const BorderSide(color: cornerColor, width: thickness)
                : BorderSide.none,
            bottom: !top
                ? const BorderSide(color: cornerColor, width: thickness)
                : BorderSide.none,
            left: left
                ? const BorderSide(color: cornerColor, width: thickness)
                : BorderSide.none,
            right: !left
                ? const BorderSide(color: cornerColor, width: thickness)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCircleAction({
    required IconData icon,
    required VoidCallback onTap,
    required double scale,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click, // <--- Add this
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50 * scale,
          width: 50 * scale,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 26 * scale),
        ),
      ),
    );
  }
}

Widget _buildBreedMatchTile(Map<String, dynamic> match) {
  final String breedName = match['breed']?.toString() ?? 'Unknown';
  final String hexColor = match['color']?.toString() ?? '#3F7795';
  final colorStr = hexColor.replaceFirst('#', '0xFF');
  final Color breedColor = Color(int.parse(colorStr));
  final num percentage = match['percentage'] ?? 0;

  // Helper function to launch the search
  Future<void> launchSearch() async {
    // Use Uri.https to safely encode the breed name for the URL
    final Uri url = Uri.https('www.google.com', '/search', {
      'q': '$breedName pet breed info',
    });

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // Fallback if the browser can't be opened
      debugPrint('Could not launch $url');
    }
  }

  return InkWell(
    onTap: launchSearch, // Tap to search!
    borderRadius: BorderRadius.circular(15),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 45,
                width: 45,
                child: CircularProgressIndicator(
                  value: percentage / 100,
                  strokeWidth: 4,
                  color: breedColor,
                  backgroundColor: Colors.grey.shade100,
                ),
              ),
              Icon(Icons.pets, size: 18, color: breedColor.withOpacity(0.6)),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breedName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF2D3142),
                  ),
                  softWrap: true, // Allows text to wrap to the lower part
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      "$percentage% Match",
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "• Tap to learn more",
                      style: TextStyle(color: Colors.blue[300], fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.open_in_new, size: 16, color: Colors.grey[300]),
        ],
      ),
    ),
  );
}
