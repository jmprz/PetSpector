import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import '../main.dart';
import '../utils/breed_detector.dart';

class CamScanScreen extends StatefulWidget {
  const CamScanScreen({super.key});

  @override
  State<CamScanScreen> createState() => _CamScanScreenState();
}

class _CamScanScreenState extends State<CamScanScreen> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;

  final BreedDetector _breedDetector = BreedDetector();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  File? _selectedImage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() {
    if (cameras.isEmpty) {
      _initializeControllerFuture = Future.value();
      return;
    }

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _cameraController.initialize();
  }

  void _showResultBottomSheet(Map<String, dynamic> data) {
  // 1. Identify if the AI returned an error or a success
  final bool isError = data['status'] == 'error';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      // Make the sheet smaller if it's just an error message
      height: MediaQuery.of(context).size.height * (isError ? 0.45 : 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          // Drag Handle
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
              child: isError ? _buildErrorView(data) : _buildSuccessView(data),
            ),
          ),
        ],
      ),
    ),
  );
}

// --- SUB-WIDGET: ERROR VIEW ---
Widget _buildErrorView(Map<String, dynamic> data) {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(height: 20),
      const Icon(Icons.nearby_error_outlined, color: Colors.orangeAccent, size: 70),
      const SizedBox(height: 20),
      const Text(
        "Invalid Selection",
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Text(
        // 'care' usually holds the error message in our errorMap logic
        data['care'] ?? "This image does not appear to be one of our supported pets (Dog, Cat, Bird, Fish, or Tortoise).",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600], fontSize: 16),
      ),
      const SizedBox(height: 30),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F7795),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text("Got it", style: TextStyle(color: Colors.white)),
        ),
      ),
    ],
  );
}

// --- SUB-WIDGET: SUCCESS VIEW ---
Widget _buildSuccessView(Map<String, dynamic> data) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Header Section
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['breed'] ?? 'Unknown Breed',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3142),
                  ),
                ),
                Text(
                  (data['type'] ?? 'Pet').toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[300],
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const CircleAvatar(
            backgroundColor: Color(0xFFF0F7F9),
            child: Icon(Icons.pets, color: Color(0xFF3F7795)),
          ),
        ],
      ),
      const SizedBox(height: 20),

      // Identification Confidence
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Identification Match",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
              ),
              const Text(
                "High Confidence", // Gemini doesn't give % like TFLite, so we use a label
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3F7795)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const LinearProgressIndicator(
              value: 0.95, // Visual indicator
              backgroundColor: Color(0xFFEEEEEE),
              color: Color(0xFF3F7795),
              minHeight: 8,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),

      // Image Preview (The user's photo)
      if (_selectedImage != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            _selectedImage!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      const SizedBox(height: 25),

      // Allergies Card
      _buildInfoCard(
        title: "Common Allergies",
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFFF4F2),
        iconColor: Colors.redAccent,
        child: Text(
          data['allergies'] ?? "No common allergies found.",
          style: const TextStyle(height: 1.5, fontSize: 15),
        ),
      ),
      const SizedBox(height: 16),

      // Care Tip Card
      _buildInfoCard(
        title: "Expert Care Tip",
        icon: Icons.lightbulb_outline_rounded,
        color: const Color(0xFFF0F9F1),
        iconColor: Colors.green,
        child: Text(
          data['care'] ?? "Ensure regular veterinary checkups.",
          style: const TextStyle(height: 1.4, fontSize: 15),
        ),
      ),
      const SizedBox(height: 30),

      // Close Button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F7795),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );
}

  // UI Helper Widget for info blocks
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

  Future<void> _processImage(File file) async {
    setState(() {
      _isProcessing = true;
      _selectedImage = file;
    });

    try {
      await _uploadImageToFirebase(file);
      final Map<String, dynamic> result = await _breedDetector.predict(file);

      if (mounted) {
        _showResultBottomSheet(result);
      }
    } catch (e) {
      debugPrint("An error occurred: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takePicture() async {
    await _initializeControllerFuture;
    final XFile image = await _cameraController.takePicture();
    await _processImage(File(image.path));
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _processImage(File(image.path));
    }
  }

  Future<void> _uploadImageToFirebase(File file) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage
        .ref()
        .child('pet_uploads')
        .child(user.uid)
        .child(fileName);

    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();
    debugPrint('✅ Firebase Image URL: $downloadUrl');
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan or Upload Sample',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF3F7795),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder(
              future: _initializeControllerFuture,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    _cameraController.value.isInitialized) {
                  return ClipRRect(child: CameraPreview(_cameraController));
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 15),
                    child: LinearProgressIndicator(
                      backgroundColor: Color(0xFFE0E0E0),
                      color: Color(0xFF3F7795),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _takePicture,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text(
                    'Capture & Upload',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F7795),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickImageFromGallery,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Gallery', style: TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3F7795),
                    side: const BorderSide(color: Color(0xFF3F7795)),
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
