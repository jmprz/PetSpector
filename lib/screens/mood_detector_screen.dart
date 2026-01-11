import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; 
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
  
  // FIX: Use XFile for platform compatibility
  XFile? _selectedXFile;
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isVideoMode = true;

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

void _initializeCamera(int index) async {
    if (cameras.isEmpty) return;
    if (_cameraController != null) await _cameraController!.dispose();

    _cameraController = CameraController(
      cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      _initializeControllerFuture = _cameraController!.initialize();
      await _initializeControllerFuture;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

 void _toggleCamera() {
    if (cameras.length < 2) return;
    _selectedCameraIndex = _selectedCameraIndex == 0 ? 1 : 0;
    _initializeCamera(_selectedCameraIndex);
  }

 Future<void> _startRecording() async {
  if (_cameraController == null || !_cameraController!.value.isInitialized) {
    debugPrint("Camera not initialized");
    return;
  }

  if (_cameraController!.value.isRecordingVideo) return;

  try {
    // Some devices need a tiny delay before starting
    await Future.delayed(const Duration(milliseconds: 100));
    await _cameraController!.startVideoRecording();
    setState(() => _isRecording = true);
  } catch (e) {
    debugPrint("Error starting video recording: $e");
    // Show snackbar so you know if it's a permission issue
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Recording Error: $e")),
    );
  }
}
 Future<void> _stopRecording() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) return;

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _selectedXFile = videoFile;
      });
      await _processMedia(videoXFile: videoFile);
    } catch (e) {
      debugPrint("Error stopping recording: $e");
      setState(() => _isRecording = false);
    }
  }


Future<void> _processMedia({XFile? videoXFile, XFile? imageXFile}) async {
    setState(() => _isProcessing = true);
    final bool isImage = imageXFile != null;
    final XFile activeFile = isImage ? imageXFile : videoXFile!;

    try {
      // Analyze using the XFile-compatible detector
      final Map<String, dynamic> result = isImage 
          ? await _moodDetector.analyzeImage(activeFile)
          : await _moodDetector.analyzeVideo(activeFile);

      if (result['status'] != 'error') {
        await _saveMoodAnalysisToHistory(result, activeFile, isImage: isImage);
      }

      if (mounted) _showResultBottomSheet(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


Future<void> _saveMoodAnalysisToHistory(
    Map<String, dynamic> result,
    XFile xFile, {
    bool isImage = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final Uint8List bytes = await xFile.readAsBytes();
      String folder = isImage ? 'mood_images' : 'mood_videos';
      String extension = isImage ? 'jpg' : 'mp4';
      String fileName = '$folder/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.$extension';

     UploadTask uploadTask = FirebaseStorage.instance
    .ref()
    .child(fileName)
    .putData(
      bytes, 
      SettableMetadata(
        contentType: isImage ? 'image/jpeg' : 'video/mp4',
        // Adding this helps some browsers/Electron wrappers handle the upload better
        customMetadata: {'userId': user.uid}, 
      ),
    );
          
      TaskSnapshot snapshot = await uploadTask;
      String mediaUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('mood_analysis').add({
        'userId': user.uid,
        'mood': result['mood'] ?? 'Unknown',
        'confidence': result['confidence'] ?? 0,
        'bodyLanguage': result['bodyLanguage'] ?? 'No data',
        'behaviorAnalysis': result['behaviorAnalysis'] ?? 'No data',
        'concerns': result['concerns'] ?? 'No concerns observed',
        'positiveSigns': result['positiveSigns'] ?? 'None detected',
        'recommendations': result['recommendations'] ?? 'No recommendations',
        'mediaUrl': mediaUrl,
        'isVideo': !isImage,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("❌ Save failed: $e");
    }
  }



Future<void> _pickVideoFromGallery() async {
    final XFile? video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (video != null) await _processMedia(videoXFile: video);
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) await _processMedia(imageXFile: image);
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
          _buildHelpRow(Icons.light_mode_outlined, "Good Lighting", "Ensure your pet is in a well-lit area for better accuracy."),
          _buildHelpRow(Icons.center_focus_weak, "Center Your Pet", "Keep the pet within the corner brackets for a clear scan."),
          _buildHelpRow(Icons.timer_outlined, "Stay Still", "Hold your phone steady while taking the video."),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3F7795),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Got it!", style: TextStyle(color: Colors.white, fontSize: 16)),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(desc, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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
    backgroundColor: Colors.transparent, // Background of the whole window
    body: Center(
      child: Container(
        // This container IS the camera screen
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
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                },
              ),
            ),

            // 2. Overlay Controls (The "Internal" AppBar)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 10,
              right: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button
                  _buildCircleAction(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.pop(context),
                    scale: 0.9, // Slightly smaller
                  ),
                  
                  // Center Title
                  Expanded(
                    child: Text(
                      _isVideoMode ? "Mood Detector (Video)" : "Mood Detector (Image)",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                      ),
                    ),
                  ),

                  // Right Actions (Mode Toggle & Info)
                  Row(
                    children: [
                      _buildCircleAction(
                        icon: _isVideoMode ? Icons.image : Icons.videocam,
                        onTap: () => setState(() => _isVideoMode = !_isVideoMode),
                        scale: 0.9,
                      ),
                      const SizedBox(width: 8),
                      _buildCircleAction(
                        icon: Icons.info_outline,
                        onTap: _showHelpModal,
                        scale: 0.9,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Scanning Frame
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
                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
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
                    icon: _isVideoMode ? Icons.video_library : Icons.photo_library,
                    onTap: _isVideoMode ? _pickVideoFromGallery : _pickImageFromGallery,
                    scale: scaleFactor,
                  ),
                  _buildShutterButton(scaleFactor), // Extracted shutter logic
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

// Helper to keep the build method clean
Widget _buildShutterButton(double scale) {
  return GestureDetector(
    onTap: _isRecording ? _stopRecording : (_isVideoMode ? _startRecording : () async {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final XFile image = await _cameraController!.takePicture();
        await _processMedia(imageXFile: image);
      }
    }),
    child: Container(
      height: 80 * scale,
      width: 80 * scale,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _isRecording ? Colors.red : Colors.white, width: 3),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _isRecording ? Colors.red : Colors.white,
          shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: _isRecording ? BorderRadius.circular(8) : null,
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

