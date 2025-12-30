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
  bool _isModelLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    _breedDetector.loadModel().then((_) async {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _isModelLoaded = true);
      }
    });
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

  Future<void> _takePicture() async {
    await _initializeControllerFuture;
    final XFile image = await _cameraController.takePicture();
    final file = File(image.path);

    setState(() {
      _isProcessing = true;
      _selectedImage = file;
    });

    try {
      // Start the upload immediately
      await _uploadImageToFirebase(file);

      // Attempt prediction separately
      if (_breedDetector.isLoaded) {
        await _breedDetector.predict(file);
      } else {
        debugPrint(
          "Model still loading, skipped prediction but upload successful.",
        );
      }
    } catch (e) {
      debugPrint("An error occurred: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return; // User cancelled the picker

    final file = File(image.path);

    setState(() {
      _isProcessing = true;
      _selectedImage = file;
    });

    try {
      // 1. Upload to Firebase FIRST (Essential)
      await _uploadImageToFirebase(file);
      debugPrint("Gallery image uploaded successfully.");

      // 2. Run Prediction SECOND (Optional/Try-Catch)
      if (_isModelLoaded) {
        final results = await _breedDetector.predict(file);
        debugPrint("Prediction Results: $results");
      } else {
        debugPrint("Model not ready for prediction yet.");
      }
    } catch (e) {
      debugPrint("Error during gallery upload/process: $e");
      // Show user feedback
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
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
        title: const Text('Scan or Upload Sample'),
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
                  return CameraPreview(_cameraController);
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_isProcessing) const LinearProgressIndicator(),
                // For the Capture Button
                ElevatedButton.icon(
                  onPressed: (_isProcessing || !_isModelLoaded)
                      ? null
                      : _takePicture,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    _isModelLoaded ? 'Capture & Upload' : 'Loading Model...',
                  ),
                ),

                const SizedBox(height: 10),

                // For the Gallery Button
                OutlinedButton.icon(
                  onPressed: (_isProcessing || !_isModelLoaded)
                      ? null
                      : _pickImageFromGallery,
                  icon: const Icon(Icons.upload),
                  label: Text(
                    _isModelLoaded ? 'Upload from Gallery' : 'Please wait...',
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
