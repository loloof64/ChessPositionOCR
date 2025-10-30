import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:opencv_core/opencv.dart' as cv;

void _log(String msg) {
  developer.log('[ChessboardOCR] $msg');
}

Future<Uint8List?> extractChessboard(Uint8List memoryImage) async {
  try {
    _log('Starting extractChessboard');

    // Decode image
    cv.Mat mat = cv.imdecode(memoryImage, cv.IMREAD_COLOR);
    if (mat.isEmpty) {
      _log('ERROR: Failed to decode image');
      mat.dispose();
      return null;
    }
    _log('Image decoded: ${mat.width}x${mat.height}');

    // Convert to grayscale
    cv.Mat gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    _log('Converted to grayscale: ${gray.width}x${gray.height}');

    // Resize for faster processing
    final scale = gray.width > gray.height
        ? 1200.0 / gray.width
        : 1200.0 / gray.height;

    cv.Mat resized;
    if (scale < 1.0) {
      final newWidth = (gray.width * scale).toInt();
      final newHeight = (gray.height * scale).toInt();
      resized = cv.resize(gray, (newWidth, newHeight));
      _log('Resized to ${resized.width}x${resized.height}');
    } else {
      resized = gray;
    }

    // Use goodFeaturesToTrack to find corner points (more robust than pattern matching)
    _log('Running goodFeaturesToTrack...');
    final corners = cv.goodFeaturesToTrack(
      resized,
      1200, // Max corners to return
      0.01, // Quality threshold
      10, // Min distance between corners
    );
    _log('Found ${corners.length} corner features');

    if (corners.length < 4) {
      _log('ERROR: Not enough corners found (need at least 4)');
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      return null;
    }

    // Refine corners to sub-pixel accuracy
    cv.cornerSubPix(resized, corners, (11, 11), (-1, -1));
    _log('Sub-pixel refinement done');

    // Find the 4 extreme corners (top-left, top-right, bottom-left, bottom-right)
    cv.Point2f? topLeft, topRight, bottomLeft, bottomRight;
    double minSum = double.infinity, maxSum = -double.infinity;
    double minDiff = double.infinity, maxDiff = -double.infinity;

    for (final pt in corners) {
      final x = pt.x;
      final y = pt.y;
      final sum = x + y; // TL vs BR
      final diff = x - y; // BL vs TR

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
        bottomLeft == null ||
        bottomRight == null) {
      _log('ERROR: Failed to identify board corners');
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      return null;
    }

    // Scale corners back to original image size if we resized
    if (scale < 1.0) {
      final invScale = 1.0 / scale;
      topLeft = cv.Point2f(topLeft.x * invScale, topLeft.y * invScale);
      topRight = cv.Point2f(topRight.x * invScale, topRight.y * invScale);
      bottomLeft = cv.Point2f(bottomLeft.x * invScale, bottomLeft.y * invScale);
      bottomRight = cv.Point2f(
        bottomRight.x * invScale,
        bottomRight.y * invScale,
      );
      _log('Scaled corners back to original resolution');
    }

    _log(
      'Corners: TL(${topLeft.x},${topLeft.y}) TR(${topRight.x},${topRight.y}) BL(${bottomLeft.x},${bottomLeft.y}) BR(${bottomRight.x},${bottomRight.y})',
    );

    // Save original corners for bounding box calculation (for cropping)
    final origTopLeft = topLeft;
    final origTopRight = topRight;
    final origBottomLeft = bottomLeft;
    final origBottomRight = bottomRight;

    // Add small margin inward to avoid partial squares at board edges
    // Calculate the center point of the board
    final centerX = (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4;
    final centerY = (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4;

    // Apply very small inward margin (0.5% to avoid partial squares at edges)
    // Reduced from 2% because it was shrinking the board too much
    const marginRatio = 0.005;
    topLeft = cv.Point2f(
      topLeft.x + (centerX - topLeft.x) * marginRatio,
      topLeft.y + (centerY - topLeft.y) * marginRatio,
    );
    topRight = cv.Point2f(
      topRight.x + (centerX - topRight.x) * marginRatio,
      topRight.y + (centerY - topRight.y) * marginRatio,
    );
    bottomLeft = cv.Point2f(
      bottomLeft.x + (centerX - bottomLeft.x) * marginRatio,
      bottomLeft.y + (centerY - bottomLeft.y) * marginRatio,
    );
    bottomRight = cv.Point2f(
      bottomRight.x + (centerX - bottomRight.x) * marginRatio,
      bottomRight.y + (centerY - bottomRight.y) * marginRatio,
    );
    _log('Applied inward margin to avoid partial squares');

    _log(
      'Corners after margin: TL(${topLeft.x},${topLeft.y}) TR(${topRight.x},${topRight.y}) BL(${bottomLeft.x},${bottomLeft.y}) BR(${bottomRight.x},${bottomRight.y})',
    );

    // Calculate output size
    final topWidth =
        ((topRight.x - topLeft.x) * (topRight.x - topLeft.x) +
                (topRight.y - topLeft.y) * (topRight.y - topLeft.y))
            .toDouble();
    final leftHeight =
        ((bottomLeft.x - topLeft.x) * (bottomLeft.x - topLeft.x) +
                (bottomLeft.y - topLeft.y) * (bottomLeft.y - topLeft.y))
            .toDouble();

    final size = (math.sqrt((topWidth + leftHeight) / 2)).toInt();
    _log('Calculated output size: $size');

    if (size < 64) {
      _log('ERROR: Size too small: $size');
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      topLeft.dispose();
      topRight.dispose();
      bottomLeft.dispose();
      bottomRight.dispose();
      return null;
    }

    // Create a bounding box from the ORIGINAL corners for cropping
    // (before margin was applied, to capture the full board)
    final minX = math
        .min(
          math.min(origTopLeft.x, origTopRight.x),
          math.min(origBottomLeft.x, origBottomRight.x),
        )
        .toInt();
    final maxX = math
        .max(
          math.max(origTopLeft.x, origTopRight.x),
          math.max(origBottomLeft.x, origBottomRight.x),
        )
        .toInt();
    final minY = math
        .min(
          math.min(origTopLeft.y, origTopRight.y),
          math.min(origBottomLeft.y, origBottomRight.y),
        )
        .toInt();
    final maxY = math
        .max(
          math.max(origTopLeft.y, origTopRight.y),
          math.max(origBottomLeft.y, origBottomRight.y),
        )
        .toInt();

    _log(
      'Bounding box: minX=$minX, maxX=$maxX, minY=$minY, maxY=$maxY, width=${maxX - minX}, height=${maxY - minY}',
    );

    // Calculate tight crop region based on detected board boundaries
    final boardWidth = maxX - minX;
    final boardHeight = maxY - minY;

    // Determine the size for the square crop based on the larger dimension
    // Add small padding (5%) to ensure we don't clip the board edges
    final paddingFactor = 1.05;
    final baseCropSize = math.max(boardWidth, boardHeight) * paddingFactor;

    // Use the calculated crop size directly (it's based on detected board)
    // Only clamp if it would exceed BOTH image dimensions
    var squareSize = baseCropSize.toInt();

    // If the calculated size is larger than what fits in the image,
    // use the largest square that fits
    if (squareSize > gray.width || squareSize > gray.height) {
      squareSize = math.min(gray.width, gray.height);
    }

    // Center the crop on the detected board
    final boardCenterX = (minX + maxX) / 2;
    final boardCenterY = (minY + maxY) / 2;

    var cropX = (boardCenterX - squareSize / 2).toInt();
    var cropY = (boardCenterY - squareSize / 2).toInt();

    // Clamp to valid image range
    cropX = math.max(0, math.min(cropX, gray.width - squareSize));
    cropY = math.max(0, math.min(cropY, gray.height - squareSize));

    // Validate crop parameters before using them
    if (cropX < 0 ||
        cropY < 0 ||
        cropX + squareSize > gray.width ||
        cropY + squareSize > gray.height) {
      _log(
        'ERROR: Invalid crop region: x=$cropX, y=$cropY, size=$squareSize, imageSize=${gray.width}x${gray.height}',
      );
      return null;
    }

    _log('Cropping region: x=$cropX, y=$cropY, size=$squareSize (square)');

    // Crop the gray image to a square region - ensure we create exactly squareSize x squareSize
    final croppedGray = cv.Mat.fromMat(
      gray,
      roi: cv.Rect(cropX, cropY, squareSize, squareSize),
    );
    _log('Cropped image created: ${croppedGray.width}x${croppedGray.height}');

    // Adjust corner points to the cropped coordinate system
    final adjustedTopLeft = cv.Point2f(topLeft.x - cropX, topLeft.y - cropY);
    final adjustedTopRight = cv.Point2f(topRight.x - cropX, topRight.y - cropY);
    final adjustedBottomLeft = cv.Point2f(
      bottomLeft.x - cropX,
      bottomLeft.y - cropY,
    );
    final adjustedBottomRight = cv.Point2f(
      bottomRight.x - cropX,
      bottomRight.y - cropY,
    );

    _log(
      'Adjusted corners in cropped space: TL(${adjustedTopLeft.x},${adjustedTopLeft.y})',
    );

    // Create perspective transformation using cropped image
    final srcPts = cv.VecPoint2f.fromList([
      cv.Point2f(adjustedTopLeft.x, adjustedTopLeft.y),
      cv.Point2f(adjustedTopRight.x, adjustedTopRight.y),
      cv.Point2f(adjustedBottomRight.x, adjustedBottomRight.y),
      cv.Point2f(adjustedBottomLeft.x, adjustedBottomLeft.y),
    ]);

    final dstPts = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(size.toDouble(), 0),
      cv.Point2f(size.toDouble(), size.toDouble()),
      cv.Point2f(0, size.toDouble()),
    ]);

    _log('Perspective transform points created (using cropped image)');

    final perspectiveMatrix = cv.getPerspectiveTransform2f(srcPts, dstPts);
    _log('Perspective matrix calculated');

    final warped = cv.warpPerspective(croppedGray, perspectiveMatrix, (
      size,
      size,
    ));
    _log('Warped image created: ${warped.width}x${warped.height}');

    // Encode to PNG
    final (success, encoded) = cv.imencode('.png', warped);
    _log('Encode success: $success, encoded size: ${encoded.length}');

    // Cleanup
    mat.dispose();
    gray.dispose();
    if (scale < 1.0) resized.dispose();
    corners.dispose();
    topLeft.dispose();
    topRight.dispose();
    bottomLeft.dispose();
    bottomRight.dispose();
    croppedGray.dispose();
    adjustedTopLeft.dispose();
    adjustedTopRight.dispose();
    adjustedBottomLeft.dispose();
    adjustedBottomRight.dispose();
    srcPts.dispose();
    dstPts.dispose();
    perspectiveMatrix.dispose();
    warped.dispose();

    if (!success || encoded.isEmpty) {
      _log('ERROR: Encoding failed or empty result');
      return null;
    }

    _log('SUCCESS: Returning image of ${encoded.length} bytes');
    return encoded;
  } catch (e) {
    _log('EXCEPTION: $e');
    return null;
  }
}
