import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart'; // Import main to access the global 'cameras' list

class CamScanScreen extends StatefulWidget {
  const CamScanScreen({super.key});

  @override
  State<CamScanScreen> createState() => _CamScanScreenState();
}

class _CamScanScreenState extends State<CamScanScreen> {
  // These are marked 'late' and initialized synchronously in initState.
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  
  // State variables for managing selected image and processing status
  File? _selectedImage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() {
    // Check if cameras list is populated from main.dart
    if (cameras.isEmpty) {
      debugPrint("No cameras available.");
      // We can create a dummy completed future if no camera is available
      _initializeControllerFuture = Future.value();
      return;
    }

    // Initialize the controller with the first available camera
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // Store the initialization Future and update state when complete
    _initializeControllerFuture = _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((e) {
      debugPrint("Camera initialization error: $e");
      // Handle permission errors or other initialization issues
      if (e is CameraException) {
        // Optionally show a user-friendly error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.description}')),
        );
      }
    });
  }

  // --- Photo Capture and Upload Methods ---

  // 1. Capture photo from the active camera feed
  Future<void> _takePicture() async {
    // Ensure the controller is initialized before attempting to take a picture
    try {
      await _initializeControllerFuture;
      if (!_cameraController.value.isInitialized) {
        throw Exception("Camera controller not initialized.");
      }
      
      setState(() {
        _isProcessing = true;
      });

      final XFile image = await _cameraController.takePicture();
      
      if (!mounted) return;
      
      // Update state with the captured image path
      setState(() {
        _selectedImage = File(image.path);
        _isProcessing = false;
      });
      
      // Navigate to the analysis screen with the captured image
      _navigateToAnalysis(File(image.path));
      
    } catch (e) {
      debugPrint(e.toString());
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to take picture. Ensure permissions are granted.')),
      );
    }
  }

  // 2. Pick image from device gallery
  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        if (!mounted) return;
        setState(() {
          _selectedImage = File(image.path);
        });
        // Navigate to the analysis screen with the selected image
        _navigateToAnalysis(File(image.path));
      }
    } catch (e) {
      debugPrint(e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick image from gallery. Check storage permissions.')),
      );
    }
  }

  // --- Next Step: Analysis and Navigation ---

  void _navigateToAnalysis(File imageFile) {
    // TODO: This is where you will implement the navigation to your result screen
    // For now, we'll just show a confirmation.
    
    // Example of a temporary confirmation message:
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Image captured/selected: ${imageFile.path.split('/').last}. Ready for AI scanning!')),
    );

    // In a real app, you would navigate here:
    // Navigator.push(context, MaterialPageRoute(
    // 	builder: (context) => AnalysisResultScreen(image: imageFile),
    // ));
  }


  @override
  void dispose() {
    // Safely dispose the controller
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
            // --- Camera Preview / Image Display Area ---
            Expanded(
              child: FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  // Check if a camera is physically available AND the future is done
                  if (cameras.isNotEmpty && snapshot.connectionState == ConnectionState.done) {
                    // Check if controller is fully initialized
                    if (_cameraController.value.isInitialized) {
                       // Display the Camera Preview, fitting it into the available space
                      return CameraPreview(_cameraController);
                    } else {
                      // Controller initialized future is done, but controller state is bad (e.g. permission denied)
                      return const Center(
                        child: Text("Camera not available or initialized.", textAlign: TextAlign.center)
                      );
                    }
                  } else if (cameras.isEmpty) {
                    // If no camera is found
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text("No camera detected on device. Please use 'Upload from Gallery'.", textAlign: TextAlign.center),
                      )
                    );
                  } else {
                    // Otherwise, display a loading indicator while waiting for the Future.
                    return const Center(child: CircularProgressIndicator());
                  }
                },
              ),
            ),

            // --- Capture/Upload Buttons ---
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  if (_isProcessing)
                    const LinearProgressIndicator(),
                    
                  // Capture Button
                  ElevatedButton.icon(
                    onPressed: _isProcessing || cameras.isEmpty || !_cameraController.value.isInitialized ? null : _takePicture,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture for Scan'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: const Color(0xFF3F7795),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 5,
                    ),
                  ),
                  
                  const SizedBox(height: 15),

                  // Upload Button (From Gallery)
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickImageFromGallery,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload from Gallery'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      foregroundColor: const Color(0xFF3F7795),
                      side: const BorderSide(color: Color(0xFF3F7795), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
