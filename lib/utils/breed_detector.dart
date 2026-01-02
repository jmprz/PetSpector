import 'dart:io';
import 'dart:convert';
import 'dart:typed_data'; // Added this import for Uint8List
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BreedDetector {
  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
  late final GenerativeModel _model;

  BreedDetector() {
    if (_apiKey.isEmpty) {
      throw Exception("API Key not found in .env file");
    }
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

    // Updated prompt to include local Philippine breeds and description
    final prompt = TextPart("""
  You are a Professional Pet Classifier specialized in local and international breeds.
  ALLOWED CATEGORIES: Cat, Dog, Tortoise, Saltwater Fish, Bird.

  SPECIAL INSTRUCTIONS:
  - Identify native Filipino dogs as "Aspin (Asong Pinoy)".
  - Identify native Filipino cats as "Puspin (Pusang Pinoy)".
  - Provide a brief, friendly description of the breed.
  - Estimate your identification accuracy as a percentage (e.g., 95).

  RETURN JSON FORMAT ONLY:
  {
    "status": "success" or "error",
    "message": "if error, explain why",
    "breed": "Breed Name",
    "accuracy": 95, 
    "description": "Brief description of the breed's characteristics",
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
    final Map<String, dynamic> data = jsonDecode(jsonText);

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