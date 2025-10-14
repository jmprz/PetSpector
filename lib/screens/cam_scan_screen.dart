import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart'; // Add this for Supabase
import '../main.dart'; // Access global camera list
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


  File? _selectedImage;
  bool _isProcessing = false;

  final SupabaseClient supabase = Supabase.instance.client;

bool _isModelLoaded = false;

@override
void initState() {
  super.initState();
  _initializeCamera();

  // Load model safely
  _breedDetector.loadModel().then((_) async {
    await Future.delayed(const Duration(seconds: 3)); // Add delay to ensure model is ready
    if (mounted) {
      setState(() => _isModelLoaded = true);
      debugPrint("✅ Model fully loaded and ready!");
    }
  }).catchError((e) {
    debugPrint("❌ Model load failed: $e");
  });
}




  void _initializeCamera() {
    if (cameras.isEmpty) {
      debugPrint("No cameras available.");
      _initializeControllerFuture = Future.value();
      return;
    }

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((e) {
      debugPrint("Camera initialization error: $e");
      if (e is CameraException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.description}')),
        );
      }
    });
  }

 // --- Capture photo from camera ---
Future<void> _takePicture() async {
  if (!_isModelLoaded) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model is still loading... please wait.')),
    );
    return;
  }

  try {
    await _initializeControllerFuture;
    final XFile image = await _cameraController.takePicture();
    final file = File(image.path);

    setState(() {
      _isProcessing = true;
      _selectedImage = file;
    });

    final prediction = await _breedDetector.predict(file);
    print("🐶 Prediction success: ${prediction.take(5)}");

    await _uploadImageToSupabase(file);
  } catch (e) {
    debugPrint("❌ Error taking picture: $e");
  } finally {
    setState(() => _isProcessing = false);
  }
}

// --- Upload image from gallery ---
Future<void> _pickImageFromGallery() async {
  if (!_isModelLoaded) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model is still loading... please wait.')),
    );
    return;
  }

  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.gallery);

  if (image == null) return;

  final file = File(image.path);

  setState(() {
    _isProcessing = true;
    _selectedImage = file;
  });

  try {
    final prediction = await _breedDetector.predict(file);
    print("🐶 Prediction success: ${prediction.take(5)}");
    await _uploadImageToSupabase(file);
  } catch (e) {
    debugPrint("❌ Error uploading image: $e");
  } finally {
    setState(() => _isProcessing = false);
  }
}

  // --- Upload image to Supabase Storage ---
  Future<void> _uploadImageToSupabase(File file) async {
    try {
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fileBytes = await file.readAsBytes();

      // Upload to your Supabase Storage bucket (e.g. 'captures')
      final response = await supabase.storage
          .from('pet_uploads') // Change this to your bucket name
          .uploadBinary(
            'uploads/$fileName',
            fileBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      if (response.isEmpty) {
        throw Exception("Upload failed: Empty response");
      }

      // Get public URL
      final publicUrl =
          supabase.storage.from('pet_uploads').getPublicUrl('uploads/$fileName');
      debugPrint('✅ Uploaded image URL: $publicUrl');
    } catch (e) {
      debugPrint('❌ Supabase upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
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
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (cameras.isNotEmpty &&
                      snapshot.connectionState == ConnectionState.done) {
                    if (_cameraController.value.isInitialized) {
                      return CameraPreview(_cameraController);
                    } else {
                      return const Center(
                          child: Text("Camera not available or initialized."));
                    }
                  } else if (cameras.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          "No camera detected. Please use 'Upload from Gallery'.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  if (_isProcessing) const LinearProgressIndicator(),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ||
                            cameras.isEmpty ||
                            !_cameraController.value.isInitialized
                        ? null
                        : _takePicture,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture & Upload'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: const Color(0xFF3F7795),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 5,
                    ),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickImageFromGallery,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload from Gallery'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      foregroundColor: const Color(0xFF3F7795),
                      side: const BorderSide(color: Color(0xFF3F7795), width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
