import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../utils/mood_detector.dart';

class MoodDetectorScreen extends StatefulWidget {
  const MoodDetectorScreen({super.key});

  @override
  State<MoodDetectorScreen> createState() => _MoodDetectorScreenState();
}

class _MoodDetectorScreenState extends State<MoodDetectorScreen> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  final MoodDetector _moodDetector = MoodDetector();
  int _selectedCameraIndex = 0;
  File? _selectedVideo;
  File? _selectedImage;
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isVideoMode = true; // Default to video mode

  @override
  void initState() {
    super.initState();
    _initializeCamera(_selectedCameraIndex);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
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

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint("Error starting video recording: $e");
    }
  }

  Future<void> _stopRecording() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _selectedVideo = File(videoFile.path);
      });
      await _processVideo(_selectedVideo!);
    } catch (e) {
      debugPrint("Error stopping video recording: $e");
      setState(() => _isRecording = false);
    }
  }

  Future<void> _processVideo(File videoFile) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final Map<String, dynamic> result = await _moodDetector.analyzeVideo(videoFile);

      if (result['status'] != 'error') {
        await _saveMoodAnalysisToHistory(result, videoFile);
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

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _isProcessing = true;
      _selectedImage = imageFile;
    });

    try {
      final Map<String, dynamic> result = await _moodDetector.analyzeImage(imageFile);

      if (result['status'] != 'error') {
        // Save image-based analysis
        await _saveMoodAnalysisToHistory(result, imageFile, isImage: true);
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

Future<void> _saveMoodAnalysisToHistory(
  Map<String, dynamic> result,
  File mediaFile, {
  bool isImage = false,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    // 1. Upload the file to Firebase Storage
    String folder = isImage ? 'mood_images' : 'mood_videos';
    String extension = isImage ? 'jpg' : 'mp4';
    String fileName = '$folder/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.$extension';

    UploadTask uploadTask = FirebaseStorage.instance
        .ref()
        .child(fileName)
        .putFile(mediaFile);
        
    TaskSnapshot snapshot = await uploadTask;
    String mediaUrl = await snapshot.ref.getDownloadURL();

    // 2. Save the metadata to Firestore
    await FirebaseFirestore.instance.collection('mood_analysis').add({
      'userId': user.uid,
      'mood': result['mood'] ?? 'Unknown',
      'confidence': result['confidence'] ?? 0,
      'bodyLanguage': result['bodyLanguage'] ?? 'No data',
      'behaviorAnalysis': result['behaviorAnalysis'] ?? 'No data',
      'concerns': result['concerns'] ?? 'No concerns observed',
      'positiveSigns': result['positiveSigns'] ?? 'None detected',
      'type': result['type'] ?? 'Unknown',
      'recommendations': result['recommendations'] ?? 'No recommendations',
      'mediaUrl': mediaUrl, // This link lets you view the video/image later
      'isVideo': !isImage,
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    debugPrint("✅ Mood analysis saved successfully!");
  } catch (e) {
    debugPrint("❌ Failed to save mood analysis: $e");
    // Optionally show a small toast or snackbar to the user
  }
}

  Future<void> _pickVideoFromGallery() async {
    final picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      await _processVideo(File(video.path));
    }
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _processImage(File(image.path));
    }
  }

  void _showResultBottomSheet(Map<String, dynamic> data) {
    final bool isError = data['status'] == 'error';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * (isError ? 0.45 : 0.9),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
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
                child: isError
                    ? _buildErrorView(data)
                    : _buildSuccessView(data),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView(Map<String, dynamic> data) {
    final int confidenceInt = data['confidence'] ?? 0;
    final double confidenceDouble = confidenceInt / 100.0;

    // Mood color mapping
    Color moodColor = _getMoodColor(data['mood'] ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mood Badge
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
        // Wrap the Text in Flexible to prevent the overflow
        Flexible( 
          child: Text(
            data['mood'] ?? 'Unknown Mood',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: moodColor,
            ),
            overflow: TextOverflow.ellipsis, // Adds "..." if still too long
          ),
        ),
      ],
    ),
  ),
),
        const SizedBox(height: 20),

        // Confidence
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

        // Info Cards
        _buildInfoCard(
          "Body Language",
          Icons.gesture,
          const Color(0xFFE3F2FD),
          Colors.blue,
          Text(data['bodyLanguage'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          "Behavior Analysis",
          Icons.psychology,
          const Color(0xFFF3E5F5),
          Colors.purple,
          Text(data['behaviorAnalysis'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          "Positive Signs",
          Icons.sentiment_very_satisfied,
          const Color(0xFFF0F9F1),
          Colors.green,
          Text(data['positiveSigns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          "Concerns",
          Icons.warning_amber_rounded,
          const Color(0xFFFFF4F2),
          Colors.redAccent,
          Text(data['concerns'] ?? ""),
        ),
        const SizedBox(height: 16),

        _buildInfoCard(
          "Recommendations",
          Icons.lightbulb_outline_rounded,
          const Color(0xFFFFF9E6),
          Colors.orange,
          Text(data['recommendations'] ?? ""),
        ),
        const SizedBox(height: 30),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F7795),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text("Done", style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(Map<String, dynamic> data) {
    return Column(
      children: [
        const Icon(
          Icons.error_outline,
          color: Colors.orangeAccent,
          size: 70,
        ),
        const Text(
          "Analysis Failed",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          data['recommendations'] ?? "Unable to analyze mood. Please try again.",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _isVideoMode ? "Mood Detector (Video)" : "Mood Detector (Image)",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(_isVideoMode ? Icons.image : Icons.videocam, color: Colors.white),
            onPressed: () {
              setState(() => _isVideoMode = !_isVideoMode);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
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
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 2),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    _isVideoMode ? Icons.video_library : Icons.photo_library,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _isVideoMode ? _pickVideoFromGallery : _pickImageFromGallery,
                ),
                GestureDetector(
                  onTap: _isRecording ? _stopRecording : (_isVideoMode ? _startRecording : () async {
                    if (_cameraController != null && _cameraController!.value.isInitialized) {
                      final XFile image = await _cameraController!.takePicture();
                      await _processImage(File(image.path));
                    }
                  }),
                  child: Container(
                    height: 70,
                    width: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isRecording ? Colors.red : Colors.white,
                        width: 4,
                      ),
                      color: _isRecording ? Colors.red.withOpacity(0.3) : Colors.white24,
                    ),
                    child: _isRecording
                        ? const Icon(Icons.stop, color: Colors.white, size: 30)
                        : Icon(
                            _isVideoMode ? Icons.videocam : Icons.camera_alt,
                            color: Colors.white,
                            size: 30,
                          ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _toggleCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

