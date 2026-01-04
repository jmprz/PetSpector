import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MoodDetector {
  late final GenerativeModel _model;

  MoodDetector() {
    String apiKey;
    try {
      apiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
    } catch (e) {
      throw Exception("DotEnv not initialized. Please ensure .env file is loaded: $e");
    }
    
    if (apiKey.isEmpty) {
      throw Exception("API Key not found in .env file. Please set GEMINI_API_KEY");
    }
    
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<Map<String, dynamic>> analyzeVideo(File videoFile) async {
    try {
      final Uint8List videoBytes = await videoFile.readAsBytes();

      final prompt = TextPart("""
You are a Professional Pet Behavior Analyst specialized in interpreting pet body language and emotional states.
ALLOWED CATEGORIES: Cat, Dog, Bird, Tortoise.

ANALYZE THE VIDEO AND DETERMINE:
- The pet's current mood/emotional state (e.g., Happy, Anxious, Excited, Calm, Playful, Scared, Content, Alert, Stressed, etc.)
- Body language indicators that support your analysis
- Behavioral patterns observed in the video
- Any potential concerns or positive signs
- Estimated confidence level for your mood assessment (0-100)

RETURN JSON FORMAT ONLY:
{
  "status": "success",
  "mood": "Primary Mood State",
  "confidence": 85,
  "bodyLanguage": "Description of key body language indicators",
  "behaviorAnalysis": "Detailed analysis of observed behaviors",
  "concerns": "Any potential concerns or if none, state 'No concerns observed'",
  "positiveSigns": "Positive behavioral indicators",
  "type": "Dog/Cat/Bird/Tortoise",
  "recommendations": "Suggestions based on the observed mood and behavior"
}
""");

      final content = [
        Content.multi([prompt, DataPart('video/mp4', videoBytes)])
      ];

      final response = await _model.generateContent(content);
      final String jsonText = response.text ?? "{}";
      final Map<String, dynamic> data = jsonDecode(jsonText);

      if (data['status'] == 'error') {
        return _errorMap(data['message'] ?? "Failed to analyze video.");
      }

      return data;
    } catch (e) {
      return _errorMap("Connection failed. Please try again.");
    }
  }

  // For image-based mood analysis (fallback)
  Future<Map<String, dynamic>> analyzeImage(File imageFile) async {
    try {
      final Uint8List imageBytes = await imageFile.readAsBytes();

      final prompt = TextPart("""
You are a Professional Pet Behavior Analyst specialized in interpreting pet body language and emotional states from images.
ALLOWED CATEGORIES: Cat, Dog, Bird, Tortoise.

ANALYZE THE IMAGE AND DETERMINE:
- The pet's current mood/emotional state (e.g., Happy, Anxious, Excited, Calm, Playful, Scared, Content, Alert, Stressed, etc.)
- Body language indicators visible in the image
- Behavioral cues observed
- Any potential concerns or positive signs
- Estimated confidence level for your mood assessment (0-100)

RETURN JSON FORMAT ONLY:
{
  "status": "success",
  "mood": "Primary Mood State",
  "confidence": 75,
  "bodyLanguage": "Description of key body language indicators visible",
  "behaviorAnalysis": "Analysis of observed behavioral cues",
  "concerns": "Any potential concerns or if none, state 'No concerns observed'",
  "positiveSigns": "Positive behavioral indicators",
  "type": "Dog/Cat/Bird/Tortoise",
  "recommendations": "Suggestions based on the observed mood",
  "note": "Analysis based on single image - video analysis provides more accurate results"
}
""");

      final content = [
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ];

      final response = await _model.generateContent(content);
      final String jsonText = response.text ?? "{}";
      final Map<String, dynamic> data = jsonDecode(jsonText);

      if (data['status'] == 'error') {
        return _errorMap(data['message'] ?? "Failed to analyze image.");
      }

      return data;
    } catch (e) {
      return _errorMap("Connection failed. Please try again.");
    }
  }

  Map<String, dynamic> _errorMap(String message) {
    return {
      'status': 'error',
      'mood': 'Unknown',
      'confidence': 0,
      'bodyLanguage': 'No data available.',
      'behaviorAnalysis': 'Analysis unavailable.',
      'concerns': 'Unable to analyze.',
      'positiveSigns': 'Unable to analyze.',
      'type': 'Unknown',
      'recommendations': message,
    };
  }
}

