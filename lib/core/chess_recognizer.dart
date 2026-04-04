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
  }

  /// [boardImage] : image of the isolated chessboard from your existing code
  /// Regardless of its size — it will be resized automatically
  Future<String> predictFen(img.Image boardImage) async {
    assert(_interpreter != null, 'Call load() first');

    // 1. Resize to 256×256 (= 8×8 tiles of 32×32)
    final resized = img.copyResize(boardImage, width: 256, height: 256);

    // 2. Extract 64 tiles of 32×32 in grayscale
    final input = _extractTiles(resized);

    // 3. Output tensor [64, 13]
    final output = List.generate(64, (_) => List.filled(13, 0.0));

    // 4. Inference
    _interpreter!.run(input, output);

    // 5. Rebuild the FEN
    return _buildFen(output);
  }

  /// Returns a tensor [64, 1024] (64 squares × 32×32 normalized pixels)
  List<List<double>> _extractTiles(img.Image board256) {
    const tileSize = 32;
    final tiles = <List<double>>[];

    // Row 0 = top of image = row 8 of FEN (white at bottom)
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final tile = img.copyCrop(
          board256,
          x: col * tileSize,
          y: row * tileSize,
          width: tileSize,
          height: tileSize,
        );
        final pixels = <double>[];
        for (int y = 0; y < tileSize; y++) {
          for (int x = 0; x < tileSize; x++) {
            final pixel = tile.getPixel(x, y);
            final gray =
                (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
            pixels.add(gray);
          }
        }
        tiles.add(pixels);
      }
    }
    return tiles; // shape [64, 1024]
  }

  String _buildFen(List<List<double>> probs) {
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
