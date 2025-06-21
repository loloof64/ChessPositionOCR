import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:opencv_core/opencv.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';

const defaultNoiseThreshold = 8000.0;

Future<(String?, String?)> predictFen(
  Uint8List memoryImage, {
  double noiseThreshold = defaultNoiseThreshold,
}) async {
  final interpreter = await Interpreter.fromAsset(
    'assets/models/chess_piece_model.tflite',
  );
  final image = img.decodeImage(memoryImage);
  if (image == null) {
    return (null, "Failed to decode image");
  }

  // Encode as JPG
  Uint8List imageBytes = img.encodeJpg(image);

  // Decode to cv.Mat (OpenCV Dart)
  cv.Mat mat = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
  // Convert to grayscale
  cv.Mat grayMat = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
  grayMat = cv.gaussianBlur(grayMat, (5, 5), 0);

  // Find chessboard corners
  final patternSize = (7, 7);
  final (found, corners) = cv.findChessboardCorners(grayMat, patternSize);

  if (!found) {
    return (null, "Failed to find chessboard corners.");
  }

  // Correct perspective
  final pointsSrc = cv.VecPoint2f.fromList([
    corners[0],
    corners[7],
    corners[56],
    corners[63],
  ]);
  final pointsDst = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(255, 0),
    cv.Point2f(0, 255),
    cv.Point2f(255, 255),
  ]);
  final perspectiveMat = cv.getPerspectiveTransform2f(pointsSrc, pointsDst);
  final warped = cv.warpPerspective(mat, perspectiveMat, (256, 256));

  // Predict pieces
  final pieces = List.generate(64, (_) => '');
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final tile = cv.Mat.fromMat(
        warped,
        roi: cv.Rect(y * 32, (y + 1) * 32, x * 32, (x + 1) * 32),
      );
      final (success, encodedBytes) = cv.imencode('.jpg', tile);
      if (!success) {
        pieces[y * 8 + x] = '';
      }
      final tileImage = img.decodeJpg(encodedBytes);
      if (tileImage == null) {
        pieces[y * 8 + x] = '';
      }
      final piece = predictTile(interpreter, tileImage!);
      pieces[y * 8 + x] = piece;
    }
  }

  return (buildFenBoard(pieces), null);
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
