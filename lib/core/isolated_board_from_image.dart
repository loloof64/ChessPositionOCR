import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:opencv_core/opencv.dart' as cv;

/*
Returns a map:
- 'src': Uint8List of the original image with detected corners (for debug)
- 'dst': Uint8List of the extracted chessboard zone (256x256)
- 'error': error message if any
*/
Future<Map<String, dynamic>> isolateChessboardZone(
  Uint8List memoryImage,
) async {
  final matResources = <cv.Mat>[];
  final vecResources = <cv.VecVec4i>[];
  final contoursList = <cv.VecPoint>[];

  try {
    // 1. Decode the input image
    debugPrint("Decoding image...");
    var src = await cv.imdecodeAsync(memoryImage, cv.IMREAD_COLOR);
    if (src.isEmpty) {
      return {'src': null, 'dst': null, 'error': "Image decoding failed"};
    }
    matResources.add(src);

    // 2. Convert image to grayscale
    debugPrint("Converting to grayscale...");
    final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
    matResources.add(gray);

    // 3. Enhance contrast using adaptive threshold
    debugPrint("Applying adaptive threshold...");
    final thresh = await cv.adaptiveThresholdAsync(
      gray,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      11,
      2,
    );
    matResources.add(thresh);

    // 4. Detect edges using Canny
    debugPrint("Detecting edges...");
    final edges = await cv.cannyAsync(thresh, 50, 150);
    matResources.add(edges);

    // 5. Dilate edges to close gaps
    debugPrint("Dilating edges...");
    final kernel = await cv.getStructuringElementAsync(cv.MORPH_RECT, (3, 3));
    matResources.add(kernel);
    final dilated = await cv.dilateAsync(edges, kernel);
    matResources.add(dilated);

    // 6. Find contours
    debugPrint("Finding contours...");
    final (contours, hierarchy) = await cv.findContoursAsync(
      dilated,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    contoursList.addAll(contours);
    vecResources.add(hierarchy);

    // 7. Filter for the largest square-like quadrilateral
    debugPrint("Filtering contours...");
    final imageArea = src.width * src.height;
    List<cv.Point>? bestQuad;
    double maxArea = 0;
    for (final contour in contours) {
      // Approximate contour to polygon
      final contourLength = await cv.arcLengthAsync(contour, true);
      final epsilon = 0.02 * contourLength;
      final approx = await cv.approxPolyDPAsync(contour, epsilon, true);

      // Check for convex quadrilateral
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final area = await cv.contourAreaAsync(approx);
        // Filter by area (at least 30% of the image) and aspect ratio (nearly square)
        if (area > 0.3 * imageArea) {
          final rect = cv.boundingRect(approx);
          final aspect = rect.width / rect.height;
          if (aspect > 0.8 && aspect < 1.2 && area > maxArea) {
            maxArea = area;
            bestQuad = List.generate(
              4,
              (i) => cv.Point(approx[i].x, approx[i].y),
            );
          }
        }
      }
      approx.dispose();
    }

    if (bestQuad == null) {
      return {'src': null, 'dst': null, 'error': "Chessboard not detected"};
    }

    // 8. Order corners: top-left, top-right, bottom-right, bottom-left
    debugPrint("Ordering corners...");
    cv.Point topLeft = bestQuad.reduce(
      (a, b) => (a.x + a.y < b.x + b.y) ? a : b,
    );
    cv.Point bottomRight = bestQuad.reduce(
      (a, b) => (a.x + a.y > b.x + b.y) ? a : b,
    );
    cv.Point topRight = bestQuad.reduce(
      (a, b) => (a.x - a.y > b.x - b.y) ? a : b,
    );
    cv.Point bottomLeft = bestQuad.reduce(
      (a, b) => (a.y - a.x > b.y - b.x) ? a : b,
    );
    final ordered = [topLeft, topRight, bottomRight, bottomLeft];

    // 9. Perspective transform to 256x256 square
    debugPrint("Calculating perspective transform...");
    final dstPoints = [
      cv.Point(0, 0),
      cv.Point(255, 0),
      cv.Point(255, 255),
      cv.Point(0, 255),
    ];
    final transform = await cv.getPerspectiveTransformAsync(
      cv.VecPoint.fromList(ordered),
      cv.VecPoint.fromList(dstPoints),
    );
    matResources.add(transform);

    debugPrint("Warping perspective...");
    final warped = await cv.warpPerspectiveAsync(src, transform, (256, 256));
    matResources.add(warped);

    // 10. Encode result image
    debugPrint("Encoding result...");
    final (success1, resultBytes) = await cv.imencodeAsync('.png', warped);
    if (!success1) {
      return {
        'src': null,
        'dst': null,
        'error': "Result image encoding failed",
      };
    }

    // 11. Draw detected corners for debug
    for (final p in bestQuad) {
      src = await cv.circleAsync(
        src,
        p,
        10,
        cv.Scalar(0, 0, 255),
        thickness: 5,
      );
    }
    final (success2, srcBytes) = await cv.imencodeAsync('.png', src);
    if (!success2) {
      return {
        'src': null,
        'dst': null,
        'error': "Source image encoding failed",
      };
    }

    return {'src': srcBytes, 'dst': resultBytes, 'error': null};
  } catch (e, stack) {
    return {'src': null, 'dst': null, 'error': "Error: $e\n$stack"};
  } finally {
    // Always clean up all allocated resources
    debugPrint("Cleaning up resources...");
    _cleanupMatList(matResources);
    _cleanupVecList(vecResources);
  }
}

// Helper function to dispose cv.Mat resources
void _cleanupMatList(List<cv.Mat> mats) {
  for (final mat in mats) {
    try {
      mat.dispose();
    } catch (e) {
      debugPrint("Mat disposal error: $e");
    }
  }
}

// Helper function to dispose cv.VecVec4i resources
void _cleanupVecList(List<cv.VecVec4i> vecs) {
  for (final vec in vecs) {
    try {
      vec.dispose();
    } catch (e) {
      debugPrint("Vec disposal error: $e");
    }
  }
}
