import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart'; // FIX: Missing import for XFile

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
      model: 'gemini-2.5-flash', // Note: Ensure version is correct (usually 1.5-flash)
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<Map<String, dynamic>> analyzeVideo(XFile video) async {
    // FIX: Added missing try block
    try {
      final Uint8List bytes = await video.readAsBytes();

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
          "bodyLanguage": "...",
          "behaviorAnalysis": "...",
          "concerns": "...",
          "positiveSigns": "...",
          "type": "Dog",
          "recommendations": "..."
        }
      """);

      final content = [
        Content.multi([prompt, DataPart('video/mp4', bytes)]) // FIX: Changed videoBytes to bytes
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

  Future<Map<String, dynamic>> analyzeImage(XFile image) async {
    // FIX: Added missing try block
    try {
      final Uint8List bytes = await image.readAsBytes();

      final prompt = TextPart("""
        You are a Professional Pet Behavior Analyst specialized in interpreting pet body language and emotional states from images.
        ALLOWED CATEGORIES: Cat, Dog, Bird, Tortoise.

        ANALYZE THE IMAGE AND DETERMINE:
        - The pet's current mood/emotional state.
        - Body language indicators, Behavioral cues, and Confidence (0-100).

        RETURN JSON FORMAT ONLY:
        {
          "status": "success",
          "mood": "...",
          "confidence": 75,
          "bodyLanguage": "...",
          "behaviorAnalysis": "...",
          "concerns": "...",
          "positiveSigns": "...",
          "type": "Cat",
          "recommendations": "..."
        }
      """);

      final content = [
        Content.multi([prompt, DataPart('image/jpeg', bytes)]) // FIX: Changed imageBytes to bytes
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