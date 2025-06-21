import 'package:chess_position_ocr/core/chessboard_image.dart';
import 'package:chess_position_ocr/core/extract_perspective_rectangle.dart';
import 'package:chess_position_ocr/core/logger.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:opencv_core/opencv.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';

const defaultNoiseThreshold = 8000.0;

/// Main integrated predictFen function
Future<String?> predictFen(
  Uint8List memoryImage, {
  double noiseThreshold = defaultNoiseThreshold,
}) async {
  final interpreter = await Interpreter.fromAsset(
    'assets/models/chess_piece_model.tflite',
  );
  final image = img.decodeImage(memoryImage);
  if (image == null) {
    throw "Failed to decode image";
  }

  // Encode as JPG
  Uint8List imageBytes = img.encodeJpg(image);

  // Decode to cv.Mat (OpenCV Dart)
  cv.Mat mat = cv.imdecode(imageBytes, cv.IMREAD_COLOR);

  // Find chessboard corners
  final patternSize = (7, 7);
  final (found, corners) = cv.findChessboardCornersSB(mat, patternSize);

  if (!found) {
    logger.e("Failed to find chessboard corners.");
    return null;
  }

  final topLeft = corners[0];
  final topRight = corners[patternSize.$1 - 1]; // last of first line
  final bottomRight = corners[corners.length - 1];
  final bottomLeft = corners[corners.length - patternSize.$1];

  final chessboardCorners = [
    [topLeft.x, topLeft.y],
    [topRight.x, topRight.y],
    [bottomRight.x, bottomRight.y],
    [bottomLeft.x, bottomLeft.y],
  ];

  // Get image region of chessboard
  final outputSize = [256, 256];

  final warpedChessboard = extractWarpedRegion(
    mat,
    chessboardCorners,
    outputSize,
  );

  final (success, newPngBytes) = cv.imencode('.png', warpedChessboard);
  if (!success) {
    throw "Failed to encode warped chessboard image";
  }
  final img.Image? correctedChessboardImage = img.decodePng(newPngBytes);

  if (correctedChessboardImage == null) {
    throw "Failed to decode corrected chessboard image";
  }

  final chessboardTiles = getChessboardTiles(
    correctedChessboardImage,
    useGrayscale: true,
  );

  final pieces = chessboardTiles
      .map((tileImage) => predictTile(interpreter, tileImage))
      .toList();

  return buildFenBoard(pieces);
}

/*
  Given the image data of a tile, try to determine what piece
  is on the tile, or if it's blank.

  Returns a tuple of (predicted FEN char, confidence)
*/
String predictTile(Interpreter interpreter, img.Image grayTileImage) {
  final inputShape = interpreter.getInputTensor(0).shape;
  final inputSize = inputShape[1];

  final resized = img.copyResizeCropSquare(grayTileImage, size: inputSize);
  List<num> input = List.generate(inputSize * inputSize, (_) => 0.0);
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      input[y * inputSize + x] = resized.getPixel(x, y).r;
    }
  }

  final output = List.filled(
    13,
    0.0,
  ); // 13 classes: [empty, P, N, B, R, Q, K, p, n, b, r, q, k]
  interpreter.run(input, output);

  // convert prediction to FEN
  const labels = [
    '1',
    'P',
    'N',
    'B',
    'R',
    'Q',
    'K',
    'p',
    'n',
    'b',
    'r',
    'q',
    'k',
  ];
  final labelIndex = output.indexWhere(
    (v) => v == output.reduce((a, b) => a > b ? a : b),
  );
  return labels[labelIndex];
}

/// Convert a flat list of 64 piece strings to FEN board part
String buildFenBoard(List<String> pieces) {
  final buffer = StringBuffer();

  for (int row = 0; row < 8; row++) {
    int emptyCount = 0;

    for (int col = 0; col < 8; col++) {
      final piece = pieces[row * 8 + col];

      if (piece == ' ' || piece == '' || piece == '1') {
        emptyCount++;
      } else {
        if (emptyCount > 0) {
          buffer.write(emptyCount);
          emptyCount = 0;
        }
        buffer.write(piece);
      }
    }

    if (emptyCount > 0) {
      buffer.write(emptyCount);
    }

    if (row < 7) {
      buffer.write('/');
    }
  }

  return buffer.toString();
}
