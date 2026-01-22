import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:opencv_core/opencv.dart' as cv;

class FenRecognizer {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Standard chess piece labels (matching order from original chessboard-recognizer model)
  // Original model label order: empty, then pieces in order R,N,B,Q,K,P (white), then r,n,b,q,k,p (black)
  static const List<String> _defaultLabels = [
    '1', // Empty square (index 0)
    'R', 'N', 'B', 'Q', 'K', 'P', // White pieces (indices 1-6)
    'r', 'n', 'b', 'q', 'k', 'p', // Black pieces (indices 7-12)
  ];

  Future<void> initialize() async {
    // If already initialized and not disposed, return early
    if (_isInitialized && !_isDisposed) {
      return;
    }

    // If disposed, reset the state to allow re-initialization
    if (_isDisposed) {
      _isDisposed = false;
    }

    // Close existing interpreter if present
    if (_interpreter != null) {
      try {
        _interpreter!.close();
      } catch (e) {
        developer.log(
          'Error closing existing interpreter: $e',
          name: 'FenRecognizer',
        );
      }
      _interpreter = null;
    }

    _isInitialized = false;

    try {
      developer.log('Loading TFLite model...', name: 'FenRecognizer');
      final options = InterpreterOptions();
      // Add delegate if needed (e.g. XNNPACK, GPU)

      _interpreter = await Interpreter.fromAsset(
        'assets/models/chess_piece_model.tflite',
        options: options,
      );

      // Log input/output shapes to help debug
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      developer.log(
        'Model Input Shape: ${inputTensor.shape}',
        name: 'FenRecognizer',
      );
      developer.log(
        'Model Input Type: ${inputTensor.type}',
        name: 'FenRecognizer',
      );
      developer.log(
        'Model Output Shape: ${outputTensor.shape}',
        name: 'FenRecognizer',
      );
      developer.log(
        'Number of classes: ${_defaultLabels.length}',
        name: 'FenRecognizer',
      );

      _labels = _defaultLabels;

      _isInitialized = true;
      developer.log(
        'FenRecognizer initialized successfully',
        name: 'FenRecognizer',
      );
    } catch (e) {
      developer.log(
        'Failed to initialize FenRecognizer: $e',
        name: 'FenRecognizer',
      );
      rethrow;
    }
  }

  Future<String> imageToFen(Uint8List boardImageBytes) async {
    if (_isDisposed) {
      throw StateError('FenRecognizer has been disposed');
    }
    if (!_isInitialized) {
      await initialize();
    }

    // Decode image using OpenCV
    final boardMat = cv.imdecode(boardImageBytes, cv.IMREAD_COLOR);
    if (boardMat.isEmpty) {
      throw Exception('Failed to decode board image');
    }

    try {
      // Resize to a standard size to ensure consistent splitting
      // 800x800 is a good size (100x100 per square)
      final resizedBoard = cv.resize(boardMat, (800, 800));

      final squareHeight = resizedBoard.height ~/ 8;
      final squareWidth = resizedBoard.width ~/ 8;

      final List<String> fenRows = [];

      // Read board from top to bottom (rank 8 to rank 1)
      for (int row = 0; row < 8; row++) {
        int emptyCount = 0;
        String rowFen = '';

        for (int col = 0; col < 8; col++) {
          // Extract square
          final x = col * squareWidth;
          final y = row * squareHeight;

          final square = cv.Mat.fromMat(
            resizedBoard,
            roi: cv.Rect(x, y, squareWidth, squareHeight),
          );

          // Preprocess for model
          // Resize to 32x32 as expected by the original model
          final resizedSquare = cv.resize(square, (32, 32));

          // Convert to input format (usually float32 [0,1] or uint8 [0,255])
          // We'll assume float32 normalized [0,1] for now as it's common for TFLite
          // But we need to check inputTensor.type.
          // For now, let's prepare a Float32List.

          var inputData = _preprocessSquare(resizedSquare, 32, 32);

          // Run inference
          // Output shape is usually [1, num_classes]
          final outputBuffer = List.filled(
            1 * _labels.length,
            0.0,
          ).reshape([1, _labels.length]);

          _interpreter!.run(inputData, outputBuffer);

          // Get predicted class
          final probs = outputBuffer[0] as List<double>;
          final maxIdx = _findMaxIndex(probs);
          final predictedLabel =
              _labels[maxIdx]; // We might need to adjust index mapping

          // Debug logging for first few squares
          if (row < 2 && col < 4) {
            developer.log(
              'Square [$row,$col]: predicted "$predictedLabel" (confidence: ${probs[maxIdx].toStringAsFixed(3)})',
              name: 'FenRecognizer',
            );
          }

          // Handle FEN construction
          if (predictedLabel == '1') {
            emptyCount++;
          } else {
            if (emptyCount > 0) {
              rowFen += emptyCount.toString();
              emptyCount = 0;
            }
            rowFen += predictedLabel;
          }

          square.dispose();
          resizedSquare.dispose();
        }

        if (emptyCount > 0) {
          rowFen += emptyCount.toString();
        }
        fenRows.add(rowFen);
      }

      resizedBoard.dispose();
      boardMat.dispose();

      // Chess FEN starts from rank 8 (top) to rank 1 (bottom)
      // If the image shows the board from white's perspective, we may need to reverse
      final finalFen = fenRows.join('/');
      developer.log('Generated FEN: $finalFen', name: 'FenRecognizer');

      return finalFen;
    } catch (e) {
      // Ensure cleanup on error
      try {
        boardMat.dispose();
      } catch (_) {
        // Ignore disposal errors
      }
      developer.log('Error in imageToFen: $e', name: 'FenRecognizer');
      rethrow;
    }
  }

  // Helper to find index of max value
  int _findMaxIndex(List<double> list) {
    int maxIndex = 0;
    double maxValue = list[0];
    for (int i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  Object _preprocessSquare(cv.Mat square, int width, int height) {
    // Convert OpenCV Mat to grayscale
    final graySquare = cv.cvtColor(square, cv.COLOR_BGR2GRAY);

    // Get raw bytes
    final bytes = graySquare.data;

    // Create input buffer
    // Assuming Float32 input [1, height, width, 1]
    final input = List.generate(
      1,
      (i) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) => [
            // Index calculation: (y * width + x)
            bytes[y * width + x] / 255.0,
          ],
        ),
      ),
    );

    graySquare.dispose();
    return input;
  }

  void dispose() {
    if (_isDisposed) return;

    try {
      _interpreter?.close();
    } catch (e) {
      developer.log('Error disposing interpreter: $e', name: 'FenRecognizer');
    }

    _interpreter = null;
    _isInitialized = false;
    _isDisposed = true;
  }

  // Helper method to flip FEN vertically (for testing different board orientations)
  static String flipFenVertically(String fen) {
    final rows = fen.split('/');
    return rows.reversed.join('/');
  }
}
