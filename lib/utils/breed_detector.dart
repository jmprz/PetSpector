import 'dart:io';
import 'dart:convert';
import 'dart:typed_data'; // Added this import for Uint8List
import 'package:google_generative_ai/google_generative_ai.dart';

class BreedDetector {
  final String _apiKey = "api-key-goes-here";
  late final GenerativeModel _model;

  BreedDetector() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Corrected version
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json', // Keep this! It's better for apps
      ),
    );
  }

  Future<Map<String, dynamic>> predict(File imageFile) async {
    try {
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // We update the prompt to ask for JSON specifically
      final prompt = TextPart("""
        You are a Strict Pet Classifier. 
        ALLOWED CATEGORIES: Cat, Dog, Tortoise, Saltwater Fish, Bird.

        TASK:
        1. Identify the breed and info.
        2. If the image is not an animal or not in the categories, set "status" to "error".

        RETURN JSON FORMAT ONLY:
        {
          "status": "success" or "error",
          "message": "if error, explain why",
          "breed": "Name",
          "type": "Cat/Dog/Tortoise/Saltwater Fish/Bird",
          "allergies": "List details",
          "care": "Tip"
        }
      """);

      final content = [
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ];

      final response = await _model.generateContent(content);
      final String jsonText = response.text ?? "{}";

      // 1. Convert the String response into a real Map
      final Map<String, dynamic> data = jsonDecode(jsonText);

      // 2. Handle the logical error we defined in the prompt
      if (data['status'] == 'error') {
        return _errorMap(data['message'] ?? "Not a supported pet.");
      }

      return data;
    } catch (e) {
      return _errorMap("Connection failed. Please try again.");
    }
  }

  // Unified error map to keep your UI from crashing
  Map<String, dynamic> _errorMap(String message) {
    return {
      'status': 'error',
      'breed': 'N/A',
      'type': 'Unknown',
      'allergies': 'No known data.',
      'care': message,
    };
  }
}