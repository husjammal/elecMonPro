import 'package:flutter_tts/flutter_tts.dart';

class VoiceOverService {
  static final VoiceOverService _instance = VoiceOverService._internal();
  factory VoiceOverService() => _instance;

  VoiceOverService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isEnabled = false;

  Future<void> initialize() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  bool get isEnabled => _isEnabled;

  Future<void> speak(String text) async {
    if (_isEnabled && text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  Future<void> speakButton(String buttonText) async {
    if (_isEnabled) {
      await speak("Button: $buttonText");
    }
  }

  Future<void> speakTextField(String label, String? value) async {
    if (_isEnabled) {
      final text = value != null && value.isNotEmpty
          ? "$label: $value"
          : "Text field: $label";
      await speak(text);
    }
  }

  Future<void> speakScreenTitle(String title) async {
    if (_isEnabled) {
      await speak("Screen: $title");
    }
  }

  Future<void> speakListItem(String itemText, int index) async {
    if (_isEnabled) {
      await speak("Item ${index + 1}: $itemText");
    }
  }

  Future<void> speakCard(String cardTitle, String? subtitle) async {
    if (_isEnabled) {
      final text = subtitle != null
          ? "$cardTitle: $subtitle"
          : cardTitle;
      await speak(text);
    }
  }

  Future<void> speakSwitch(String label, bool isOn) async {
    if (_isEnabled) {
      final state = isOn ? "enabled" : "disabled";
      await speak("$label: $state");
    }
  }

  Future<void> speakDropdown(String label, String selectedValue) async {
    if (_isEnabled) {
      await speak("$label: $selectedValue");
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  Future<void> pause() async {
    await _flutterTts.pause();
  }


  void dispose() {
    _flutterTts.stop();
  }
}