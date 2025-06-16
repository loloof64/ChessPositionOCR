import 'dart:typed_data';
import 'package:ml_linalg/matrix.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:image/image.dart' as img;

/// Finds the outer corners (top, left, bottom, right) from sequences of lines
List<int> getOuterCorners(List<int> seqX, List<int> seqY) {
  int top = seqY.first;
  int left = seqX.first;
  int bottom = seqY.last;
  int right = seqX.last;
  return [top, left, bottom, right];
}

/// Warp chessboard bounding box crop to perfect square image.
/// For now, crop bounding box and resize to 512x512 pixels.
img.Image warpBoardToSquare(img.Image source, List<int> refinedCorners) {
  // refinedCorners = [top, left, bottom, right]
  final top = refinedCorners[0];
  final left = refinedCorners[1];
  final bottom = refinedCorners[2];
  final right = refinedCorners[3];

  final width = right - left;
  final height = bottom - top;

  // Crop bounding box
  final cropped = img.copyCrop(
    source,
    x: left,
    y: top,
    width: width,
    height: height,
  );

  // Resize to square 512x512
  final warped = img.copyResize(cropped, width: 512, height: 512);

  return warped;
}

/// Extract 64 square images (8x8 grid) from a square board image (warped to 256x256)
List<img.Image> extractSquares(img.Image boardImage) {
  const gridSize = 8;
  final squareWidth = (boardImage.width / gridSize).floor();
  final squareHeight = (boardImage.height / gridSize).floor();
  final squares = <img.Image>[];

  for (int row = 0; row < gridSize; row++) {
    for (int col = 0; col < gridSize; col++) {
      final square = img.copyCrop(
        boardImage,
        x: col * squareWidth,
        y: row * squareHeight,
        width: squareWidth,
        height: squareHeight,
      );
      squares.add(square);
    }
  }

  return squares;
}

/// Helper: Convert img.Image grayscale to Matrix&lt;double&gt; for detectChessboardCorners/// Converts a grayscale img.Image into a Matrix&lt;double&gt; (row-major)
Matrix imageToMatrix(img.Image image) {
  final rows = List.generate(image.height, (y) {
    return List.generate(image.width, (x) {
      final pixel = image.getPixel(x, y);
      return pixel.r.toDouble(); // grayscale from red channel
    });
  });
  return Matrix.fromList(rows);
}

final List<String> classToFen = [
  '', // 0 - empty
  'P', 'N', 'B', 'R', 'Q', 'K', // 1-6 - white
  'p', 'n', 'b', 'r', 'q', 'k', // 7-12 - black
];

/// Predicts a chess piece from a square image using TFLite
Future<String> predictPieceFromSquare(img.Image squareImage) async {
  // Resize to model input size (e.g. 64x64)
  final inputSize = 64;
  final resized = img.copyResize(
    squareImage,
    width: inputSize,
    height: inputSize,
  );

  // Convert to grayscale float32 tensor [1, 64, 64, 1]
  final input = List.generate(inputSize * inputSize, (i) {
    final x = i % inputSize;
    final y = i ~/ inputSize;
    final pixel = resized.getPixel(x, y);
    final gray = pixel.r / 255.0; // normalize
    return gray;
  });

  final inputTensor = Float32List.fromList(input);
  final inputBuffer = inputTensor.buffer.asFloat32List();

  final interpreter = await Interpreter.fromAsset(
    'assets/models/chess_piece_model.tflite',
  );
  final output = List.filled(13, 0.0).reshape([1, 13]); // output: [1, 13]

  interpreter.run(inputBuffer.reshape([1, 64, 64, 1]), output);

  final prediction = output[0]; // Get logits/probabilities
  final predictedIndex = prediction.indexWhere(
    (val) => val == prediction.reduce((a, b) => a > b ? a : b),
  );

  return classToFen[predictedIndex];
}
