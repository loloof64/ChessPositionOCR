import 'package:flutter/services.dart';

import 'package:opencv_core/opencv.dart' as cv;

Future<(Uint8List?, String?)> isolateBoardPhoto(Uint8List memoryImage) async {
  // Decode to cv.Mat (OpenCV Dart)
  cv.Mat mat = await cv.imdecodeAsync(memoryImage, cv.IMREAD_COLOR);
  // Convert to grayscale
  cv.Mat grayMat = await cv.cvtColorAsync(mat, cv.COLOR_BGR2GRAY);

  final median = await cv.medianBlurAsync(grayMat, 21);

  final (_, thresh) = await cv.thresholdAsync(
    median,
    0,
    255,
    cv.THRESH_BINARY + cv.THRESH_OTSU,
  );

  // Find contours
  final (contours, _) = await cv.findContoursAsync(
    thresh,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );

  // Filter for largest quadrilateral
  cv.VecPoint? boardContour;
  double maxArea = 0;
  for (final contour in contours) {
    final peri = await cv.arcLengthAsync(contour, true);
    final approx = await cv.approxPolyDPAsync(contour, 0.02 * peri, true);
    if (approx.length == 4) {
      final area = await cv.contourAreaAsync(approx);
      if (area > maxArea) {
        maxArea = area;
        boardContour = approx;
      }
    }
  }

  if (boardContour == null) {
    median.dispose();
    mat.dispose();
    grayMat.dispose();
    thresh.dispose();
    boardContour?.dispose();
    return (null, "Failed to find chessboard contours");
  }

  // Convert to a usable Dart list of points
  final List<cv.Point2f> points = boardContour
      .toList()
      .map((pt) => cv.Point2f(pt.x.toDouble(), pt.y.toDouble()))
      .toList();

  // Sort the points to order: top-left, top-right, bottom-right, bottom-left
  cv.Point2f? topLeft, topRight, bottomRight, bottomLeft;
  double minSum = double.infinity, maxSum = -double.infinity;
  double minDiff = double.infinity, maxDiff = -double.infinity;

  for (final pt in points) {
    final sum = pt.x + pt.y;
    final diff = pt.x - pt.y;

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

  if (topLeft == null ||
      topRight == null ||
      bottomRight == null ||
      bottomLeft == null) {
    median.dispose();
    mat.dispose();
    thresh.dispose();
    boardContour.dispose();
    topLeft?.dispose();
    topRight?.dispose();
    bottomRight?.dispose();
    bottomLeft?.dispose();
    grayMat.dispose();
    return (null, "Failed to find chessboard corners");
  }

  // Now we have the points in the correct order
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
  final perspectiveMat = await cv.getPerspectiveTransform2fAsync(
    pointsSrc,
    pointsDst,
  );
  final warped = await cv.warpPerspectiveAsync(grayMat, perspectiveMat, (
    256,
    256,
  ));

  // convert warped to Uint8List
  final (success, warpedBytes) = await cv.imencodeAsync('.jpg', thresh);
  if (!success) {
    median.dispose();
    mat.dispose();
    grayMat.dispose();
    thresh.dispose();
    boardContour.dispose();
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

  median.dispose();
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
