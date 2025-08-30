import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/database_provider.dart';
import '../models/meter_reading.dart';
import '../services/ocr_service.dart';
import '../services/voice_over_service.dart';

class AddReadingScreen extends StatefulWidget {
  final MeterReading? reading; // null for add, not null for edit

  const AddReadingScreen({super.key, this.reading});

  @override
  State<AddReadingScreen> createState() => _AddReadingScreenState();
}

class _AddReadingScreenState extends State<AddReadingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  final _notesController = TextEditingController();
  final VoiceOverService _voiceOverService = VoiceOverService();
  DateTime _selectedDate = DateTime.now();
  File? _selectedImage;
  bool _isLoading = false;
  bool _isProcessingOCR = false;
  String? _extractedText;
  double? _extractedValue;
  bool _ocrEnabled = true;

  @override
  void initState() {
    super.initState();
    _voiceOverService.initialize();
    _loadOCRSetting();
    if (widget.reading != null) {
      _readingController.text = widget.reading!.readingValue.toString();
      _notesController.text = widget.reading!.notes ?? '';
      _selectedDate = widget.reading!.date;
      // Note: photoPath is stored, but we don't load the image file here
    }
  }

  Future<void> _loadOCRSetting() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser != null) {
      await databaseProvider.loadAppSettings(authProvider.currentUser!.id);
      final settings = databaseProvider.appSettings;
      if (settings != null && mounted) {
        setState(() {
          _ocrEnabled = settings.ocrEnabled;
        });
      }
    }
  }

  @override
  void dispose() {
    _readingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      setState(() {
        _selectedImage = imageFile;
        _extractedText = null;
        _extractedValue = null;
      });

      if (_ocrEnabled) {
        await _processOCR(imageFile);
      }
    }
  }

  Future<void> _processOCR(File imageFile) async {
    setState(() {
      _isProcessingOCR = true;
    });

    try {
      final ocrService = OCRService();
      final extractedText = await ocrService.extractTextFromImage(imageFile);
      final extractedValue = ocrService.extractNumericValue(extractedText);

      if (mounted) {
        setState(() {
          _extractedText = extractedText;
          _extractedValue = extractedValue;
          _isProcessingOCR = false;
        });

        if (extractedValue != null) {
          await _showOCRConfirmationDialog(extractedValue, extractedText);
        } else {
          _showOCRFailureDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingOCR = false;
        });
        _showOCRFailureDialog();
      }
    }
  }

  Future<void> _showOCRConfirmationDialog(double value, String text) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OCR Result'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extracted value: $value'),
            const SizedBox(height: 8),
            const Text('Extracted text:'),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Edit Manually'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use This Value'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _readingController.text = value.toString();
      });
    }
  }

  void _showOCRFailureDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OCR Failed'),
        content: const Text('Could not extract a numeric value from the image. Please enter the reading manually.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<String?> _saveImageToLocalStorage(File image) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${directory.path}/meter_photos');
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedImage = await image.copy('${imageDir.path}/$fileName');
      return savedImage.path;
    } catch (e) {
      print('Error saving image: $e');
      return null;
    }
  }

  Future<double> _calculateConsumption(double currentReading) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

    if (authProvider.currentUser == null) return currentReading;

    final lastReading = await databaseProvider.getLastMeterReading(authProvider.currentUser!.id);
    if (lastReading != null) {
      return currentReading - lastReading.readingValue;
    }
    return currentReading; // First reading
  }

  Future<void> _saveReading() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);

      if (authProvider.currentUser == null) return;

      final readingValue = double.parse(_readingController.text);
      final consumption = await _calculateConsumption(readingValue);

      String? photoPath;
      if (_selectedImage != null) {
        photoPath = await _saveImageToLocalStorage(_selectedImage!);
      } else if (widget.reading != null) {
        photoPath = widget.reading!.photoPath;
      }

      final reading = MeterReading(
        id: widget.reading?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        userId: authProvider.currentUser!.id,
        readingValue: readingValue,
        date: _selectedDate,
        photoPath: photoPath,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        consumption: consumption,
        isManual: _extractedValue == null || _readingController.text != _extractedValue.toString(),
      );

      if (widget.reading == null) {
        await databaseProvider.addReading(reading);
      } else {
        await databaseProvider.updateReading(reading);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving reading: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size and orientation for responsive design
    final screenSize = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;

    // Define responsive breakpoints
    final isTablet = screenSize.width >= 600;
    final isLandscape = orientation == Orientation.landscape;

    // Responsive padding and spacing
    final horizontalPadding = isTablet ? 32.0 : 16.0;
    final verticalSpacing = isTablet ? 24.0 : 16.0;
    final buttonSpacing = isTablet ? 32.0 : 16.0;

    // Announce screen title for voice-over
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _voiceOverService.speakScreenTitle(widget.reading == null ? 'Add Reading' : 'Edit Reading');
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reading == null ? 'Add Reading' : 'Edit Reading'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(horizontalPadding),
            child: Form(
              key: _formKey,
              child: Column(
            children: [
              Semantics(
                label: 'Meter reading value in kilowatt hours',
                hint: 'Enter the meter reading value',
                child: TextFormField(
                  controller: _readingController,
                  decoration: const InputDecoration(
                    labelText: 'Meter Reading Value (kWh)',
                    hintText: 'Enter the meter reading',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a reading value';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                  onChanged: (value) => _voiceOverService.speakTextField('Meter reading', value),
                ),
              ),
              SizedBox(height: verticalSpacing),
              Semantics(
                label: 'Notes about this reading',
                hint: 'Optional notes field',
                child: TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'Add any notes about this reading',
                  ),
                  maxLines: isTablet ? 4 : 3,
                  onChanged: (value) => _voiceOverService.speakTextField('Notes', value),
                ),
              ),
              SizedBox(height: verticalSpacing),
              Semantics(
                label: 'Date and time selector: ${_selectedDate.toString()}',
                hint: 'Tap to select date and time',
                button: true,
                child: ListTile(
                  minVerticalPadding: 12, // Increase touch target
                  title: const Text('Date & Time'),
                  subtitle: Text(_selectedDate.toString()),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    _voiceOverService.speakButton('Date and time selector');
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(_selectedDate),
                      );
                      if (time != null) {
                        setState(() {
                          _selectedDate = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                        _voiceOverService.speak('Date updated to ${_selectedDate.toString()}');
                      }
                    }
                  },
                ),
              ),
              SizedBox(height: verticalSpacing),
              Semantics(
                header: true,
                child: const Text('Photo Attachment'),
              ),
              SizedBox(height: verticalSpacing / 2),
              Row(
                children: [
                  Semantics(
                    label: 'Take photo with camera',
                    hint: 'Opens camera to take a photo of the meter',
                    button: true,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _voiceOverService.speakButton('Camera');
                        _pickImage(ImageSource.camera);
                      },
                      icon: const Icon(Icons.camera),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(isTablet ? 140 : 120, isTablet ? 56 : 48), // Responsive touch target
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: 'Select photo from gallery',
                    hint: 'Opens gallery to select a photo of the meter',
                    button: true,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _voiceOverService.speakButton('Gallery');
                        _pickImage(ImageSource.gallery);
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(isTablet ? 140 : 120, isTablet ? 56 : 48), // Responsive touch target
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedImage != null) ...[
                SizedBox(height: verticalSpacing),
                Semantics(
                  label: 'Selected meter photo',
                  image: true,
                  child: Image.file(
                    _selectedImage!,
                    height: isTablet ? 300 : 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (_isProcessingOCR) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    label: 'Processing OCR to extract text from image',
                    liveRegion: true,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 8),
                        Text('Processing OCR...'),
                      ],
                    ),
                  ),
                ],
                if (_extractedText != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    label: 'OCR results: ${_extractedText!}${_extractedValue != null ? ', detected value: ${_extractedValue!.toStringAsFixed(2)}' : ''}',
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Extracted Text:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _extractedText!,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_extractedValue != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Detected Value: ${_extractedValue!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ] else if (widget.reading?.photoPath != null) ...[
                SizedBox(height: verticalSpacing),
                const Text('Existing photo attached'),
              ],
              SizedBox(height: buttonSpacing),
              Semantics(
                label: widget.reading == null ? 'Add reading button' : 'Update reading button',
                hint: 'Saves the meter reading',
                button: true,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () {
                    _voiceOverService.speakButton(widget.reading == null ? 'Add Reading' : 'Update Reading');
                    _saveReading();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, isTablet ? 56 : 48), // Responsive touch target
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(widget.reading == null ? 'Add Reading' : 'Update Reading'),
                ),
              ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}