import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:opencv_core/opencv.dart' as cv;

class FenRecognizer {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  bool _isDisposed = false;

  // Standard chess piece labels from linrock/chessboard-recognizer constants.py
  // FEN_CHARS = '1RNBQKPrnbqkp'
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

    developer.log(
      'Input board size: ${boardMat.width}x${boardMat.height}',
      name: 'FenRecognizer',
    );

    try {
      // Resize to 256x256 to match the original chessboard-recognizer training data
      // The original model was trained on 256x256 chessboard images (32x32 per square)
      final resizedBoard = cv.resize(boardMat, (256, 256));

      developer.log(
        'Board resized to: ${resizedBoard.width}x${resizedBoard.height}',
        name: 'FenRecognizer',
      );

      // Save a copy of the resized board for debugging (optional)
      developer.log(
        'Original board aspect ratio: ${(boardMat.width / boardMat.height).toStringAsFixed(3)} (${boardMat.width}x${boardMat.height})',
        name: 'FenRecognizer',
      );

      final squareHeight = resizedBoard.height ~/ 8; // 32
      final squareWidth = resizedBoard.width ~/ 8; // 32

      developer.log(
        'Board divided into ${squareWidth}x$squareHeight squares. Board size: ${resizedBoard.width}x${resizedBoard.height}',
        name: 'FenRecognizer',
      );

      // Check if we can extract all 8 rows without going out of bounds
      final maxY = 7 * squareHeight + squareHeight;
      developer.log(
        'Square extraction check: maxY=$maxY, boardHeight=${resizedBoard.height}, squareHeight=$squareHeight',
        name: 'FenRecognizer',
      );
      if (maxY > resizedBoard.height) {
        developer.log(
          'WARNING: Bottom squares may be out of bounds. MaxY: $maxY, BoardHeight: ${resizedBoard.height}',
          name: 'FenRecognizer',
        );
      }

      // Debug: Check if bottom squares are accessible
      for (int testRow = 4; testRow < 8; testRow++) {
        final testY = testRow * squareHeight;
        developer.log(
          'Row $testRow Y-coordinate: $testY (max allowed: ${resizedBoard.height - squareHeight})',
          name: 'FenRecognizer',
        );
        if (testY + squareHeight > resizedBoard.height) {
          developer.log(
            'ERROR: Row $testRow will be out of bounds!',
            name: 'FenRecognizer',
          );
        }
      }

      final List<String> fenRows = [];

      // Read board from top to bottom (rank 8 to rank 1)
      for (int row = 0; row < 8; row++) {
        int emptyCount = 0;
        String rowFen = '';

        for (int col = 0; col < 8; col++) {
          // Extract square
          final x = col * squareWidth;
          final y = row * squareHeight;

          // Check bounds before extraction
          if (x + squareWidth > resizedBoard.width ||
              y + squareHeight > resizedBoard.height) {
            developer.log(
              'BOUNDS ERROR: Square [$row,$col] out of bounds: ($x,$y) + (${squareWidth}x$squareHeight) > ${resizedBoard.width}x${resizedBoard.height}',
              name: 'FenRecognizer',
            );
            // Skip this square or use empty
            if (emptyCount > 0) {
              rowFen += emptyCount.toString();
              emptyCount = 0;
            }
            emptyCount++;
            continue;
          }

          // Log extraction for bottom rows
          if (row >= 4) {
            developer.log(
              'Extracting square [$row,$col] at ($x,$y) size ${squareWidth}x$squareHeight from ${resizedBoard.width}x${resizedBoard.height}',
              name: 'FenRecognizer',
            );
          }

          final square = cv.Mat.fromMat(
            resizedBoard,
            roi: cv.Rect(x.toInt(), y.toInt(), squareWidth, squareHeight),
          );

          // Check if bottom squares are valid
          if (row >= 4) {
            developer.log(
              'Square [$row,$col] extracted: ${square.width}x${square.height}, isEmpty: ${square.isEmpty}',
              name: 'FenRecognizer',
            );
          }

          // Check if the square is valid (not empty/null)
          if (row >= 6) {
            developer.log(
              'Square [$row,$col] extracted: ${square.width}x${square.height}, isEmpty: ${square.isEmpty}',
              name: 'FenRecognizer',
            );
          }

          // Preprocess for model - square is already 32x32 since board is 256x256
          var inputData = _preprocessSquare(square, 32, 32);

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

          // Always log all squares to debug white piece detection issue
          final probsStr = probs
              .asMap()
              .entries
              .where((e) => e.value > 0.05) // Show probabilities > 5%
              .map((e) => '${_labels[e.key]}:${e.value.toStringAsFixed(3)}')
              .join(', ');

          developer.log(
            'Square [$row,$col]: predicted "$predictedLabel" (confidence: ${probs[maxIdx].toStringAsFixed(3)}), top probs: $probsStr',
            name: 'FenRecognizer',
          );

          // Handle FEN construction with confidence threshold
          // If confidence is too low, treat as empty
          const double confidenceThreshold =
              0.52; // Fine-tuned to reduce false positives
          if (predictedLabel == '1' || probs[maxIdx] < confidenceThreshold) {
            emptyCount++;
          } else {
            if (emptyCount > 0) {
              rowFen += emptyCount.toString();
              emptyCount = 0;
            }
            rowFen += predictedLabel;
          }

          square.dispose();
        }

        if (emptyCount > 0) {
          rowFen += emptyCount.toString();
        }
        fenRows.add(rowFen);
      }

      resizedBoard.dispose();
      boardMat.dispose();

      // Debug: Log the 8x8 grid of predictions
      developer.log('=== 8x8 Board Grid ===', name: 'FenRecognizer');
      for (int row = 0; row < 8; row++) {
        developer.log(
          'Rank ${8 - row}: ${fenRows[row]}',
          name: 'FenRecognizer',
        );
      }

      // Chess FEN starts from rank 8 (top) to rank 1 (bottom)
      // Try both normal and reversed orientation to handle board rotation
      final normalFen = fenRows.join('/');
      final reversedFen = fenRows.reversed.join('/');

      developer.log(
        'Generated FEN (normal): $normalFen',
        name: 'FenRecognizer',
      );
      developer.log(
        'Generated FEN (reversed): $reversedFen',
        name: 'FenRecognizer',
      );

      final finalFen = normalFen;
      developer.log('Generated FEN: $finalFen', name: 'FenRecognizer');

      // Log FEN rows for debugging
      for (int i = 0; i < fenRows.length; i++) {
        developer.log('Rank ${8 - i}: ${fenRows[i]}', name: 'FenRecognizer');
      }

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
    // Convert to grayscale first
    final graySquare = cv.cvtColor(square, cv.COLOR_BGR2GRAY);

    // Apply histogram equalization to normalize contrast
    final enhanced = cv.equalizeHist(graySquare);

    // Get raw bytes from enhanced image
    final Uint8List bytes = Uint8List.fromList(enhanced.data);

    // Create input buffer matching TFLite expected shape [1, 32, 32, 1]
    final inputList = Float32List(1 * height * width * 1);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        // Normalize pixel values to [0, 1]
        inputList[idx] = bytes[idx] / 255.0;
      }
    }

    // Reshape to [1, 32, 32, 1]
    final input = inputList.reshape([1, height, width, 1]);

    graySquare.dispose();
    enhanced.dispose();
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
