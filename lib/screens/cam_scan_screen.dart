import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../utils/breed_detector.dart';

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
  File? _selectedImage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera(_selectedCameraIndex);
  }

  void _initializeCamera(int index) {
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _toggleCamera() {
    if (cameras.length < 2) return;
    _selectedCameraIndex = _selectedCameraIndex == 0 ? 1 : 0;
    _initializeCamera(_selectedCameraIndex);
  }

  // --- CORE LOGIC: PROCESSING & SAVING ---

  Future<void> _processImage(File file) async {
    setState(() {
      _isProcessing = true;
      _selectedImage = file;
    });

    try {
      final Map<String, dynamic> result = await _breedDetector.predict(file);
      
      if (result['status'] != 'error') {
        await _saveScanToHistory(result, file);
      }

      if (mounted) {
        _showResultBottomSheet(result);
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveScanToHistory(Map<String, dynamic> result, File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String fileName = 'pet_uploads/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      UploadTask uploadTask = FirebaseStorage.instance.ref().child(fileName).putFile(imageFile);
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
      });
    } catch (e) {
      debugPrint("❌ Failed to save history: $e");
    }
  }

  // --- UI: BOTTOM SHEETS & CARDS ---

  void _showResultBottomSheet(Map<String, dynamic> data) {
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
            Container(
              margin: const EdgeInsets.only(top: 12),
              height: 5, width: 50,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
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

  Widget _buildSuccessView(Map<String, dynamic> data) {
    final int accuracyInt = data['accuracy'] ?? 0;
    final double accuracyDouble = accuracyInt / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedImage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(_selectedImage!, height: 250, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
        Text(data['breed'] ?? 'Unknown Breed', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        Text((data['type'] ?? 'Pet').toString().toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blueGrey[300])),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(data['description'] ?? "", style: TextStyle(fontSize: 15, color: Colors.grey[700], fontStyle: FontStyle.italic)),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Identification Match", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text("$accuracyInt%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3F7795))),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: accuracyDouble, backgroundColor: const Color(0xFFEEEEEE), color: const Color(0xFF3F7795)),
        const SizedBox(height: 25),
        _buildInfoCard("Common Allergies", Icons.warning_amber_rounded, const Color(0xFFFFF4F2), Colors.redAccent, Text(data['allergies'] ?? "")),
        const SizedBox(height: 16),
        _buildInfoCard("Care Tips", Icons.lightbulb_outline_rounded, const Color(0xFFF0F9F1), Colors.green, Text(data['care'] ?? "")),
        const SizedBox(height: 30),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F7795)), child: const Text("Done", style: TextStyle(color: Colors.white)))),
      ],
    );
  }

  Widget _buildErrorView(Map<String, dynamic> data) {
    return Column(
      children: [
        const Icon(Icons.nearby_error_outlined, color: Colors.orangeAccent, size: 70),
        const Text("Invalid Selection", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(data['care'] ?? "Not a supported pet.", textAlign: TextAlign.center),
        const SizedBox(height: 30),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Got it")),
      ],
    );
  }

  Widget _buildInfoCard(String title, IconData icon, Color bg, Color ic, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 20, color: ic), const SizedBox(width: 8), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: ic))]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  // --- ACTIONS ---

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    final XFile image = await _cameraController!.takePicture();
    await _processImage(File(image.path));
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) await _processImage(File(image.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pet Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && _cameraController != null) {
                  return CameraPreview(_cameraController!);
                }
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              },
            ),
          ),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.white54, width: 2), borderRadius: BorderRadius.circular(30)),
            ),
          ),
          if (_isProcessing)
            Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.photo_library, color: Colors.white, size: 30), onPressed: _pickImageFromGallery),
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(height: 70, width: 70, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: Colors.white24)),
                ),
                IconButton(icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 30), onPressed: _toggleCamera),
              ],
            ),
          ),
        ],
      ),
    );
  }
}