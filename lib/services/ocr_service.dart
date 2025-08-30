import 'dart:io';
import 'package:google_ml_kit/google_ml_kit.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final TextRecognizer _textRecognizer = GoogleMlKit.vision.textRecognizer();

  Future<String> extractTextFromImage(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      throw Exception('Failed to extract text from image: $e');
    }
  }

  double? extractNumericValue(String text) {
    // Regular expression to find decimal numbers (including integers)
    final RegExp numericRegex = RegExp(r'\b\d+(\.\d+)?\b');

    final matches = numericRegex.allMatches(text);
    if (matches.isEmpty) return null;

    // Find the largest numeric value (assuming meter readings are positive and increasing)
    double maxValue = 0.0;
    for (final match in matches) {
      final value = double.tryParse(match.group(0)!);
      if (value != null && value > maxValue) {
        maxValue = value;
      }
    }

    return maxValue > 0 ? maxValue : null;
  }

  Future<double?> processMeterPhoto(File imageFile) async {
    try {
      final extractedText = await extractTextFromImage(imageFile);
      return extractNumericValue(extractedText);
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}