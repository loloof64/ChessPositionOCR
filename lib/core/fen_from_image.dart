import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'package:opencv_core/opencv.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';

Future<(String?, String?)> predictFen(Uint8List memoryImage) async {
  final interpreter = await Interpreter.fromAsset(
    'assets/models/chess_piece_model.tflite',
  );

  // Decode to cv.Mat (OpenCV Dart)
  cv.Mat mat = cv.imdecode(memoryImage, cv.IMREAD_COLOR);
  // Convert to grayscale
  cv.Mat grayMat = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);

  // Find chessboard corners
  final corners = cv.goodFeaturesToTrack(
    grayMat,
    1200, // Number of corners to return
    0.01, // Minimal accepted quality of corners
    10, // Minimum possible Euclidean distance between corners
  );

  cv.Point2f? topLeft, topRight, bottomLeft, bottomRight;
  double minSum = double.infinity, maxSum = -double.infinity;
  double minDiff = double.infinity, maxDiff = -double.infinity;

  for (final pt in corners) {
    final x = pt.x;
    final y = pt.y;
    final sum = x + y;
    final diff = x - y;

    if (sum < minSum) {
      minSum = sum;
      topLeft = pt;
    }
    if (sum > maxSum) {
      maxSum = sum;
      bottomRight = pt;
    }
    if (diff < minDiff) {
      minDiff = diff;
      bottomLeft = pt;
    }
    if (diff > maxDiff) {
      maxDiff = diff;
      topRight = pt;
    }
  }

  final found =
      topLeft != null &&
      topRight != null &&
      bottomLeft != null &&
      bottomRight != null;
  if (!found) {
    mat.dispose();
    grayMat.dispose();
    topLeft?.dispose();
    topRight?.dispose();
    bottomLeft?.dispose();
    bottomRight?.dispose();
    return (null, "Failed to find chessboard corners");
  }

  final chessboardCorners = [topLeft, topRight, bottomRight, bottomLeft];

  final pointsSrc = cv.VecPoint2f.fromList(
    chessboardCorners.map((pt) => cv.Point2f(pt.x, pt.y)).toList(),
  );

  // Correct perspective
  final pointsDst = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(255, 0),
    cv.Point2f(255, 255),
    cv.Point2f(0, 255),
  ]);
  final perspectiveMat = cv.getPerspectiveTransform2f(pointsSrc, pointsDst);
  final warped = cv.warpPerspective(grayMat, perspectiveMat, (256, 256));

  // Predict pieces
  final pieces = List.generate(64, (_) => '');
  for (int y = 0; y < 8; y++) {
    for (int x = 0; x < 8; x++) {
      final tile = cv.Mat.fromMat(warped, roi: cv.Rect(x * 32, y * 32, 32, 32));
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

  mat.dispose();
  grayMat.dispose();
  topLeft.dispose();
  topRight.dispose();
  bottomLeft.dispose();
  bottomRight.dispose();
  pointsSrc.dispose();
  pointsDst.dispose();
  perspectiveMat.dispose();
  warped.dispose();

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

  // Resize to model input size
  final resized = img.copyResizeCropSquare(grayTileImage, size: inputSize);

  // Prepare input as a 4D tensor: [1, inputSize, inputSize, 1]
  final input = List.generate(
    1,
    (_) => List.generate(
      inputSize,
      (y) => List.generate(
        inputSize,
        (x) => [resized.getPixel(x, y).r.toDouble()],
      ),
    ),
  );

  final output = List.generate(1, (_) => List.filled(13, 0.0)); // 13 classes
  final scores = output[0];

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
  final labelIndex = scores.indexWhere(
    (v) => v == scores.reduce((a, b) => a > b ? a : b),
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
