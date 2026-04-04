import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const List<String> kLabels = [
  'b', 'k', 'n', 'p', 'q', 'r', // 0-5  black pieces
  'B', 'K', 'N', 'P', 'Q', 'R', // 6-11 white pieces
  '1', // 12   empty square
];

class ChessRecognizer {
  Interpreter? _interpreter;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/chess_classifier.tflite',
    );

    // Log actual model tensor details so we know the expected shapes
    final inputTensors = _interpreter!.getInputTensors();
    for (int i = 0; i < inputTensors.length; i++) {
      final t = inputTensors[i];
      developer.log(
        'Input tensor $i: name=${t.name}, shape=${t.shape}, type=${t.type}',
        name: 'ChessRecognizer',
      );
    }
    final outputTensors = _interpreter!.getOutputTensors();
    for (int i = 0; i < outputTensors.length; i++) {
      final t = outputTensors[i];
      developer.log(
        'Output tensor $i: name=${t.name}, shape=${t.shape}, type=${t.type}',
        name: 'ChessRecognizer',
      );
    }
  }

  /// [boardImage] : image of the isolated chessboard from your existing code
  /// Regardless of its size — it will be resized automatically
  Future<String> predictFen(img.Image boardImage) async {
    if (_interpreter == null) {
      await load();
    }

    // 1. Get board dimensions for per-tile extraction
    final boardW = boardImage.width;
    final boardH = boardImage.height;
    final tileW = boardW ~/ 8;
    final tileH = boardH ~/ 8;

    // 2. Classify each of the 64 tiles individually
    //    Model input: [1, 32, 32, 1], output: [1, 13]
    final probs = <List<double>>[];

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        // Extract tile at native resolution, then resize to 32×32
        final rawTile = img.copyCrop(
          boardImage,
          x: col * tileW,
          y: row * tileH,
          width: tileW,
          height: tileH,
        );
        final tile = img.copyResize(
          rawTile,
          width: 32,
          height: 32,
          interpolation: img.Interpolation.cubic,
        );

        // Build input [1, 32, 32, 1] as flat Float32List (1024 floats)
        final inputBuffer = Float32List(32 * 32);
        for (int y = 0; y < 32; y++) {
          for (int x = 0; x < 32; x++) {
            final pixel = tile.getPixel(x, y);
            inputBuffer[y * 32 + x] =
                (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
          }
        }

        // Per-tile normalization: zero mean, unit std
        double mean = 0.0;
        for (final v in inputBuffer) {
          mean += v;
        }
        mean /= inputBuffer.length;
        double variance = 0.0;
        for (final v in inputBuffer) {
          variance += (v - mean) * (v - mean);
        }
        variance /= inputBuffer.length;
        final std = variance > 1e-6 ? math.sqrt(variance) : 1.0;
        for (int i = 0; i < inputBuffer.length; i++) {
          inputBuffer[i] = (inputBuffer[i] - mean) / std;
        }

        // Output [1, 13] as flat Float32List (13 floats)
        final outputBuffer = Float32List(13);

        // Run inference for this single tile
        _interpreter!.run(inputBuffer.buffer, outputBuffer.buffer);

        probs.add(outputBuffer.toList());
      }
    }
    return _buildFen(probs);
  }

  String _buildFen(
    List<List<double>> probs, {
    double confidenceThreshold = 0.45,
  }) {
    final buffer = StringBuffer();
    int emptyCount = 0;

    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final tileProbs = probs[row * 8 + col];

        int bestIdx = 0;
        double bestVal = tileProbs[0];
        for (int i = 1; i < 13; i++) {
          if (tileProbs[i] > bestVal) {
            bestVal = tileProbs[i];
            bestIdx = i;
          }
        }

        // If confidence is below threshold, treat as empty square
        if (bestVal < confidenceThreshold) {
          bestIdx = 12;
        }

        if (bestIdx == 12) {
          emptyCount++;
        } else {
          if (emptyCount > 0) {
            buffer.write(emptyCount);
            emptyCount = 0;
          }
          buffer.write(kLabels[bestIdx]);
        }
      }
      if (emptyCount > 0) {
        buffer.write(emptyCount);
        emptyCount = 0;
      }
      if (row < 7) buffer.write('/');
    }

    buffer.write(' w - - 0 1');
    return buffer.toString();
  }

  void dispose() => _interpreter?.close();
}
