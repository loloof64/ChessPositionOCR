import 'package:flutter/services.dart';

import 'package:opencv_core/opencv.dart' as cv;

const defaultNoiseThreshold = 8000.0;

Future<(Uint8List?, String?)> isolateBoardPhoto(
  Uint8List memoryImage, {
  double noiseThreshold = defaultNoiseThreshold,
}) async {
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

  // convert warped to Uint8List
  final (success, warpedBytes) = cv.imencode('.jpg', warped);
  if (!success) {
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

    return (null, "Failed to encode warped image");
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

  return (warpedBytes, null);
}
