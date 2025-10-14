import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class BreedDetector {
  late Interpreter _interpreter;
  bool _isLoaded = false;
Future<void> loadModel() async {
  try {
    print("⏳ Loading TFLite model...");
    _interpreter = await Interpreter.fromAsset('mobilenet_v2.tflite');
    _isLoaded = true;
    print("✅ Model loaded successfully!");
  } catch (e) {
    print("❌ Model load failed: $e");
  }
}

  bool get isLoaded => _isLoaded;

  Future<List<double>> predict(File imageFile) async {
    if (!_isLoaded) throw Exception("Model not loaded yet!");

    final imageBytes = await imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes)!;
    final resized = img.copyResize(image, width: 224, height: 224);

    final input = List.generate(
      1,
      (_) => List.generate(
        224,
        (_) => List.generate(
          224,
          (_) => List.generate(3, (_) => 0.0),
        ),
      ),
    );

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x] = [
          pixel.r / 255.0,
          pixel.g / 255.0,
          pixel.b / 255.0,
        ];
      }
    }

    final output = List.filled(1000, 0.0).reshape([1, 1000]);
    _interpreter.run(input, output);
    return output[0];
  }
}
