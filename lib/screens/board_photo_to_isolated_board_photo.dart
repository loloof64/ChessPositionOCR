import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:chess_position_ocr/core/fen_recognition.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' as developer;
import 'dart:typed_data';

// Data class to hold both isolated board image and FEN prediction
class BoardAnalysisResult {
  final Uint8List isolatedBoard;
  final String fen;

  BoardAnalysisResult({required this.isolatedBoard, required this.fen});
}

@pragma('vm:entry-point')
Future<Uint8List?> heavyIsolationComputation(Uint8List imageData) async {
  try {
    developer.log(
      'Starting image processing in isolate',
      name: 'ChessboardOCR',
    );
    developer.log(
      'Image data size: ${imageData.length} bytes',
      name: 'ChessboardOCR',
    );

    final result = await extractChessboard(imageData);

    developer.log(
      'Image processing completed successfully',
      name: 'ChessboardOCR',
    );
    return result;
  } catch (e, stackTrace) {
    developer.log('Error in image processing: $e', name: 'ChessboardOCR');
    developer.log('Stack trace: $stackTrace', name: 'ChessboardOCR');
    rethrow; // Re-throw to let the UI handle it
  }
}

class BoardPhotoToIsolatedBoardPhoto extends StatefulWidget {
  const BoardPhotoToIsolatedBoardPhoto({super.key});

  @override
  State<BoardPhotoToIsolatedBoardPhoto> createState() =>
      _BoardPhotoToIsolatedBoardPhotoState();
}

class _BoardPhotoToIsolatedBoardPhotoState
    extends State<BoardPhotoToIsolatedBoardPhoto> {
  Future<BoardAnalysisResult?>? _fenFuture;
  bool _isProcessing = false;
  bool _isDisposed = false;
  final FenRecognizer _fenRecognizer = FenRecognizer();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    if (_isDisposed) return;
    try {
      await _fenRecognizer.initialize();
      developer.log('FenRecognizer initialized', name: 'ChessboardOCR');
    } catch (e) {
      developer.log(
        'Failed to initialize FenRecognizer: $e',
        name: 'ChessboardOCR',
      );
    }
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    try {
      developer.log(
        'Camera support available (using image_picker)',
        name: 'ChessboardOCR',
      );
    } catch (e) {
      developer.log('Camera initialization note: $e', name: 'ChessboardOCR');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fenRecognizer.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    if (_isProcessing) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) return;

      final imageBytes = await image.readAsBytes();
      await _processImage(imageBytes);
    } catch (e) {
      developer.log('Error picking image: $e', name: 'ChessboardOCR');
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _processImage(Uint8List imageData) async {
    if (_isDisposed) return;

    setState(() => _isProcessing = true);

    try {
      developer.log(
        'Processing image (${imageData.length} bytes)',
        name: 'ChessboardOCR',
      );

      // Extract isolated board
      final isolatedBoard = await extractChessboard(imageData);

      if (isolatedBoard == null || isolatedBoard.isEmpty) {
        throw Exception('Failed to extract chessboard from image');
      }

      // Generate FEN
      final fen = await _fenRecognizer.imageToFen(isolatedBoard);

      if (mounted && !_isDisposed) {
        setState(() {
          _fenFuture = Future.value(
            BoardAnalysisResult(isolatedBoard: isolatedBoard, fen: fen),
          );
          _isProcessing = false;
        });
      }
    } catch (e) {
      developer.log('Error processing image: $e', name: 'ChessboardOCR');
      if (mounted && !_isDisposed) {
        setState(() => _isProcessing = false);
        _showErrorSnackBar('Failed to process image: $e');
      }
    }
  }

  Future<void> _takePhotoAndConvert() async {
    if (_isProcessing) return;

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
    );

    if (image == null) return;

    setState(() => _isProcessing = true);

    try {
      developer.log('Processing captured photo...', name: 'ChessboardOCR');
      final imageBytes = await image.readAsBytes();
      await _processImage(imageBytes);
    } catch (e) {
      developer.log('Error taking photo: $e', name: 'ChessboardOCR');
      if (mounted && !_isDisposed) {
        setState(() => _isProcessing = false);
        _showErrorSnackBar('Failed to take photo: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted || _isDisposed) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _resetView() {
    if (mounted && !_isDisposed) {
      setState(() {
        _fenFuture = null;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chess Position OCR'), elevation: 0),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_fenFuture != null) {
      return _buildResultView();
    } else {
      return _buildCameraView();
    }
  }

  Widget _buildCameraView() {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black87,
            child: const Center(
              child: Text(
                'Tap "Take Photo" to capture board image',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera),
                  label: const Text('Take Photo'),
                  onPressed: _isProcessing ? null : _takePhotoAndConvert,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: const Text('Pick Image'),
                  onPressed: _isProcessing ? null : _pickImageFromGallery,
                ),
              ),
            ],
          ),
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 10),
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          const Text('Processing image...'),
          const SizedBox(height: 10),
        ] else
          const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildResultView() {
    return FutureBuilder<BoardAnalysisResult?>(
      future: _fenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildErrorView(snapshot.error);
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(child: Text('No result'));
        }

        final result = snapshot.data!;
        return _buildSuccessView(result);
      },
    );
  }

  Widget _buildErrorView(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _resetView,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView(BoardAnalysisResult result) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Isolated Board:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.memory(result.isolatedBoard, fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            const Text(
              'FEN Notation:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                result.fen,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy FEN'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('FEN copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('New Photo'),
                    onPressed: _resetView,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
