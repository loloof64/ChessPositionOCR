import 'dart:typed_data';
import 'package:opencv_core/opencv.dart' as cv;

// Returns a map with keys: 'src' (Uint8List), 'dst' (Uint8List), 'error' (String)
Future<Map<String, dynamic>> extractChessboard(Uint8List memoryImage) async {
  final matResources = <cv.Mat>[];
  final contoursList = <cv.VecPoint>[];

  try {
    // 1. Decode image
    var src = await cv.imdecodeAsync(memoryImage, cv.IMREAD_COLOR);
    if (src.isEmpty) {
      return {'src': null, 'dst': null, 'error': "Image decoding failed"};
    }
    matResources.add(src);

    // 2. Convert to grayscale
    final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
    matResources.add(gray);

    // 3. Find contours
    final (contours, _) = await cv.findContoursAsync(
      gray,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    contoursList.addAll(contours);

    // Draw contours in src
    await cv.drawContoursAsync(
      src,
      contours,
      -1,
      cv.Scalar(0, 255, 0),
      thickness: 2,
    );

    final (okSrc, srcBytes) = await cv.imencodeAsync('.png', src);
    if (!okSrc) {
      return {
        'src': null,
        'dst': null,
        'error': "Source image encoding failed",
      };
    }

    // 4. Find largest convex quadrilateral with aspect ratio ~1
    List<cv.Point>? bestQuad;
    double maxArea = 0;
    for (final contour in contours) {
      final contourLength = await cv.arcLengthAsync(contour, true);
      final epsilon = 0.02 * contourLength;
      final approx = await cv.approxPolyDPAsync(contour, epsilon, true);

      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final area = await cv.contourAreaAsync(approx);
        final rect = await cv.minAreaRectAsync(approx);
        final aspect = rect.size.width / rect.size.height;
        final aspectRatio = aspect < 1 ? 1 / aspect : aspect;
        if (area > maxArea && aspectRatio < 1.2) {
          maxArea = area;
          bestQuad = List.generate(
            4,
            (i) => cv.Point(approx[i].x, approx[i].y),
          );
        }
      }
      approx.dispose();
    }

    if (bestQuad == null) {
      return {'src': srcBytes, 'dst': null, 'error': "Chessboard not detected"};
    }

    // 5. Sort corners (top-left, top-right, bottom-right, bottom-left)
    final ordered = _orderCorners(bestQuad);

    // 6. Perspective transform
    const size = 256;
    final dstPoints = [
      cv.Point(0, 0),
      cv.Point(size - 1, 0),
      cv.Point(size - 1, size - 1),
      cv.Point(0, size - 1),
    ];
    final transform = await cv.getPerspectiveTransformAsync(
      cv.VecPoint.fromList(ordered),
      cv.VecPoint.fromList(dstPoints),
    );
    matResources.add(transform);

    final warped = await cv.warpPerspectiveAsync(src, transform, (size, size));
    matResources.add(warped);

    // 7. Encode result
    final (ok1, dstBytes) = await cv.imencodeAsync('.png', warped);
    if (!ok1) {
      return {
        'src': srcBytes,
        'dst': null,
        'error': "Result image encoding failed",
      };
    }

    // 8. Draw detected corners on source for debugging
    for (final p in bestQuad) {
      src = await cv.circleAsync(
        src,
        p,
        10,
        cv.Scalar(0, 0, 255),
        thickness: 5,
      );
    }

    return {'src': srcBytes, 'dst': dstBytes, 'error': null};
  } catch (e, stack) {
    return {'src': null, 'dst': null, 'error': "Error: $e\n$stack"};
  } finally {
    _cleanupMatList(matResources);
  }
}

// Utility: Order corners as [topLeft, topRight, bottomRight, bottomLeft]
List<cv.Point> _orderCorners(List<cv.Point> quad) {
  quad.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
  final topLeft = quad[0];
  final bottomRight = quad[3];
  quad.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
  final bottomLeft = quad[0];
  final topRight = quad[3];
  return [topLeft, topRight, bottomRight, bottomLeft];
}

void _cleanupMatList(List<cv.Mat> mats) {
  for (final mat in mats) {
    try {
      mat.dispose();
    } catch (_) {}
  }
}
