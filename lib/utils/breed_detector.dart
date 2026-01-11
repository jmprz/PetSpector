import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart'; 

class BreedDetector {
  late final GenerativeModel _model;

  BreedDetector() {
    String apiKey;
    try {
      apiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
    } catch (e) {
      throw Exception("DotEnv not initialized: $e");
    }
    
    if (apiKey.isEmpty) {
      throw Exception("API Key not found in .env file.");
    }
    
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Note: Check version name (usually 1.5-flash)
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  // FIX: Change 'File imageFile' to 'XFile image'
  Future<Map<String, dynamic>> predict(XFile image) async {
    try {
      // FIX: readAsBytes() works on both Web and Mobile!
      final Uint8List imageBytes = await image.readAsBytes();

      final prompt = TextPart("""
      You are a Professional Pet Classifier specialized in local and international breeds.
      ALLOWED CATEGORIES: Cat, Dog, Tortoise, Saltwater Fish, Bird.

      SPECIAL INSTRUCTIONS:
      - Identify native Filipino dogs as "Aspin (Asong Pinoy)".
      - Identify native Filipino cats as "Puspin (Pusang Pinoy)".
      - MIXED BREEDS: Identify specific mix details.
      - Provide a brief description and identification accuracy percentage.

      RETURN JSON FORMAT ONLY:
      {
       "status": "success",
  "breed": "Primary Breed Name",
  "accuracy": 92, 
  "description": "...",
  "type": "Dog",
  "allergies": "...",
  "care": "...",
  "matches": [
    {"breed": "Primary Breed", "percentage": 70, "color": "#3F7795"},
    {"breed": "Secondary Breed", "percentage": 20, "color": "#6DA0BD"},
    {"breed": "Other", "percentage": 10, "color": "#9CC3D9"}
  ]
}
      """);

      final content = [
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
      ];

      final response = await _model.generateContent(content);
      final String jsonText = response.text ?? "{}";
      final Map<String, dynamic> data = jsonDecode(jsonText);

      if (data['status'] == 'error') {
        return _errorMap(data['message'] ?? "Not a supported pet.");
      }

      return data;
    } catch (e) {
      print("Gemini Error: $e");
      return _errorMap("Connection failed. Please try again.");
    }
  }

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