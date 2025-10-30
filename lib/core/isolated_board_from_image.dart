import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:opencv_core/opencv.dart' as cv;

enum ChessboardExtractionError {
  imageDecodeFailed,
  notEnoughCorners,
  boardTooSmall,
  boardTooDistorted,
  outputSizeTooSmall,
  encodingFailed,
  unexpectedError,
}

class ChessboardExtractionException implements Exception {
  final ChessboardExtractionError errorType;
  final String? details;

  ChessboardExtractionException(this.errorType, {this.details});

  @override
  String toString() =>
      'ChessboardExtractionException: $errorType${details != null ? ' ($details)' : ''}';

  /// Get user-friendly message for UI display
  String getUserMessage() {
    switch (errorType) {
      case ChessboardExtractionError.imageDecodeFailed:
        return 'Failed to decode image. Please try again.';
      case ChessboardExtractionError.notEnoughCorners:
        return 'Could not detect chessboard. Please ensure the board is clearly visible and well-lit.';
      case ChessboardExtractionError.boardTooSmall:
        return 'Board too small. Please get closer to the chessboard.';
      case ChessboardExtractionError.boardTooDistorted:
        return 'Board appears too distorted. Please capture the board more straight-on.';
      case ChessboardExtractionError.outputSizeTooSmall:
        return 'Detected board area too small. Please move closer to the board.';
      case ChessboardExtractionError.encodingFailed:
        return 'Failed to process the image. Please try again.';
      case ChessboardExtractionError.unexpectedError:
        return details ?? 'An unexpected error occurred. Please try again.';
    }
  }
}

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
      throw ChessboardExtractionException(
        ChessboardExtractionError.imageDecodeFailed,
      );
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
      800, // Max corners to return (reduced to focus on strongest features)
      0.02, // Quality threshold (increased for better corner quality)
      12, // Min distance between corners (increased to reduce noise)
    );
    _log('Found ${corners.length} corner features');

    if (corners.length < 4) {
      _log('ERROR: Not enough corners found (need at least 4)');
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      throw ChessboardExtractionException(
        ChessboardExtractionError.notEnoughCorners,
      );
    }

    // Refine corners to sub-pixel accuracy
    cv.cornerSubPix(resized, corners, (11, 11), (-1, -1));
    _log('Sub-pixel refinement done');

    // Find the 4 extreme corners using a more robust method
    // First, convert to List for easier manipulation
    final cornersList = List<cv.Point2f>.generate(
      corners.length,
      (i) => corners[i],
    );

    // Sort by x+y (top-left to bottom-right diagonal)
    cornersList.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final topLeftCandidates = cornersList
        .take(math.min(20, cornersList.length ~/ 4))
        .toList();
    final bottomRightCandidates = cornersList.reversed
        .take(math.min(20, cornersList.length ~/ 4))
        .toList();

    // Sort by x-y (top-right to bottom-left diagonal)
    cornersList.sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));
    final bottomLeftCandidates = cornersList
        .take(math.min(20, cornersList.length ~/ 4))
        .toList();
    final topRightCandidates = cornersList.reversed
        .take(math.min(20, cornersList.length ~/ 4))
        .toList();

    // Find the most extreme points from candidates (most reliable corners)
    var topLeft = topLeftCandidates.reduce(
      (curr, next) => (curr.x + curr.y < next.x + next.y) ? curr : next,
    );
    var bottomRight = bottomRightCandidates.reduce(
      (curr, next) => (curr.x + curr.y > next.x + next.y) ? curr : next,
    );
    var bottomLeft = bottomLeftCandidates.reduce(
      (curr, next) => (curr.x - curr.y < next.x - next.y) ? curr : next,
    );
    var topRight = topRightCandidates.reduce(
      (curr, next) => (curr.x - curr.y > next.x - next.y) ? curr : next,
    );

    _log(
      'Selected corners from candidate pools (${topLeftCandidates.length}, ${topRightCandidates.length}, ${bottomLeftCandidates.length}, ${bottomRightCandidates.length} candidates)',
    );

    // Validate that corners form a reasonable quadrilateral
    final width1 = math.sqrt(
      math.pow(topRight.x - topLeft.x, 2) + math.pow(topRight.y - topLeft.y, 2),
    );
    final width2 = math.sqrt(
      math.pow(bottomRight.x - bottomLeft.x, 2) +
          math.pow(bottomRight.y - bottomLeft.y, 2),
    );
    final height1 = math.sqrt(
      math.pow(bottomLeft.x - topLeft.x, 2) +
          math.pow(bottomLeft.y - topLeft.y, 2),
    );
    final height2 = math.sqrt(
      math.pow(bottomRight.x - topRight.x, 2) +
          math.pow(bottomRight.y - topRight.y, 2),
    );

    // Check if opposite sides are roughly similar (within 80% tolerance)
    final widthRatio = width1 > width2 ? width1 / width2 : width2 / width1;
    final heightRatio = height1 > height2
        ? height1 / height2
        : height2 / height1;

    if (widthRatio > 1.8 || heightRatio > 1.8) {
      _log(
        'WARNING: Detected corners may be inaccurate (width ratio: ${widthRatio.toStringAsFixed(2)}, height ratio: ${heightRatio.toStringAsFixed(2)})',
      );
      _log(
        'This may result in poor quality extraction - try repositioning camera',
      );
    }

    // Check if the board is too small (likely a false detection)
    final avgWidth = (width1 + width2) / 2;
    final avgHeight = (height1 + height2) / 2;
    final minDimension = math.min(avgWidth, avgHeight);

    if (minDimension < 100) {
      _log(
        'ERROR: Detected board is too small (${minDimension.toStringAsFixed(0)} pixels). Please get closer to the board.',
      );
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      throw ChessboardExtractionException(
        ChessboardExtractionError.boardTooSmall,
        details: '${minDimension.toStringAsFixed(0)} pixels',
      );
    }

    // Additional check: Verify corners form a proper quadrilateral (not crossed)
    // Calculate the cross product to check if corners are in correct order
    final vec1x = topRight.x - topLeft.x;
    final vec1y = topRight.y - topLeft.y;
    final vec2x = bottomLeft.x - topLeft.x;
    final vec2y = bottomLeft.y - topLeft.y;
    final cross1 = vec1x * vec2y - vec1y * vec2x;

    final vec3x = bottomRight.x - topRight.x;
    final vec3y = bottomRight.y - topRight.y;
    final vec4x = bottomLeft.x - topRight.x;
    final vec4y = bottomLeft.y - topRight.y;
    final cross2 = vec3x * vec4y - vec3y * vec4x;

    // Both cross products should have the same sign for a convex quadrilateral
    if ((cross1 > 0 && cross2 < 0) || (cross1 < 0 && cross2 > 0)) {
      _log(
        'WARNING: Detected corners form a crossed quadrilateral. This may indicate incorrect corner detection.',
      );
      _log(
        'Try capturing the board from a different angle or with better lighting',
      );
    }

    _log(
      'Corner validation: widthRatio=${widthRatio.toStringAsFixed(2)}, heightRatio=${heightRatio.toStringAsFixed(2)}, minDim=${minDimension.toStringAsFixed(0)}',
    );

    // Calculate a quality score (0-100) based on corner detection metrics
    // Ratio score: penalize distorted quadrilaterals (ratio > 1.0)
    // Perfect ratio (1.0) = 50 points, ratio of 2.0 = 0 points
    final maxRatio = math.max(widthRatio, heightRatio);
    final ratioScore = math.max(0, 50 * (2.0 - maxRatio)).clamp(0, 50);

    // Size score: reward larger boards (more pixels = more accurate)
    // 100 pixels = 0 points, 200+ pixels = 50 points
    final sizeScore = ((minDimension - 100) / 100 * 50).clamp(0, 50);

    final qualityScore = (ratioScore + sizeScore).toInt().clamp(0, 100);

    _log(
      'Detection quality score: $qualityScore/100 (ratio: ${ratioScore.toInt()}, size: ${sizeScore.toInt()})',
    );

    if (qualityScore < 60) {
      _log(
        'NOTICE: Moderate quality detection (score: $qualityScore/100). Consider repositioning the camera for better results.',
      );
    }

    if (maxRatio > 1.15) {
      _log(
        'WARNING: Distortion detected (ratio: ${maxRatio.toStringAsFixed(2)}). May affect quality. Try capturing more straight-on.',
      );
    }

    // Reject captures with severe distortion (ratio > 1.2)
    // These typically result in poor quality extractions due to incorrect corner detection
    if (maxRatio > 1.2) {
      _log(
        'ERROR: Corner detection too distorted (ratio: ${maxRatio.toStringAsFixed(2)}). Please capture the board more straight-on for better corner detection.',
      );
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      topLeft.dispose();
      topRight.dispose();
      bottomLeft.dispose();
      bottomRight.dispose();
      throw ChessboardExtractionException(
        ChessboardExtractionError.boardTooDistorted,
        details: 'ratio: ${maxRatio.toStringAsFixed(2)}',
      );
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

    // Apply inward margin (1.5% to trim background noise at board edges)
    // This helps remove partial squares and background at the board perimeter
    const marginRatio = 0.015;
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
    final bottomWidth =
        ((bottomRight.x - bottomLeft.x) * (bottomRight.x - bottomLeft.x) +
                (bottomRight.y - bottomLeft.y) * (bottomRight.y - bottomLeft.y))
            .toDouble();
    final leftHeight =
        ((bottomLeft.x - topLeft.x) * (bottomLeft.x - topLeft.x) +
                (bottomLeft.y - topLeft.y) * (bottomLeft.y - topLeft.y))
            .toDouble();
    final rightHeight =
        ((bottomRight.x - topRight.x) * (bottomRight.x - topRight.x) +
                (bottomRight.y - topRight.y) * (bottomRight.y - topRight.y))
            .toDouble();

    // Calculate output size - use MAXIMUM of width and height to ensure square output
    // A chessboard is always square, so we should force square output after perspective correction
    final detectedWidth = (math.sqrt((topWidth + bottomWidth) / 2)).toInt();
    final detectedHeight = (math.sqrt((leftHeight + rightHeight) / 2)).toInt();

    // Use the larger dimension to avoid losing detail, and force square output
    final outputSize = math.max(detectedWidth, detectedHeight);
    _log(
      'Calculated output size: ${outputSize}x$outputSize (from detected ${detectedWidth}x$detectedHeight)',
    );

    if (outputSize < 64) {
      _log('ERROR: Output size too small: ${outputSize}x$outputSize');
      mat.dispose();
      gray.dispose();
      if (scale < 1.0) resized.dispose();
      corners.dispose();
      topLeft.dispose();
      topRight.dispose();
      bottomLeft.dispose();
      bottomRight.dispose();
      throw ChessboardExtractionException(
        ChessboardExtractionError.outputSizeTooSmall,
        details: '${outputSize}x$outputSize',
      );
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

    // Add padding (5%) to ensure we don't clip the board edges
    final paddingFactor = 1.05;
    final cropWidth = (boardWidth * paddingFactor).toInt();
    final cropHeight = (boardHeight * paddingFactor).toInt();

    // Center the crop on the detected board
    final boardCenterX = (minX + maxX) / 2;
    final boardCenterY = (minY + maxY) / 2;

    var cropX = (boardCenterX - cropWidth / 2).toInt();
    var cropY = (boardCenterY - cropHeight / 2).toInt();

    // Clamp to valid image range
    cropX = math.max(0, math.min(cropX, gray.width - cropWidth));
    cropY = math.max(0, math.min(cropY, gray.height - cropHeight));

    // Validate crop parameters before using them
    if (cropX < 0 ||
        cropY < 0 ||
        cropX + cropWidth > gray.width ||
        cropY + cropHeight > gray.height ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      _log(
        'ERROR: Invalid crop region: x=$cropX, y=$cropY, w=$cropWidth, h=$cropHeight, imageSize=${gray.width}x${gray.height}',
      );
      return null;
    }

    _log(
      'Cropping region: x=$cropX, y=$cropY, w=$cropWidth, h=$cropHeight (rectangular)',
    );

    // Crop the gray image to a rectangular region that encompasses the board
    final croppedGray = cv.Mat.fromMat(
      gray,
      roi: cv.Rect(cropX, cropY, cropWidth, cropHeight),
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
      cv.Point2f(outputSize.toDouble(), 0),
      cv.Point2f(outputSize.toDouble(), outputSize.toDouble()),
      cv.Point2f(0, outputSize.toDouble()),
    ]);

    _log(
      'Perspective transform points created (using cropped image, square output)',
    );

    final perspectiveMatrix = cv.getPerspectiveTransform2f(srcPts, dstPts);
    _log('Perspective matrix calculated');

    final warped = cv.warpPerspective(croppedGray, perspectiveMatrix, (
      outputSize,
      outputSize,
    ));
    _log('Warped image created: ${warped.width}x${warped.height} (square)');

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
      throw ChessboardExtractionException(
        ChessboardExtractionError.encodingFailed,
      );
    }

    _log('SUCCESS: Returning image of ${encoded.length} bytes');
    return encoded;
  } catch (e) {
    _log('EXCEPTION: $e');
    // Re-throw if it's already our custom exception
    if (e is ChessboardExtractionException) {
      rethrow;
    }
    throw ChessboardExtractionException(
      ChessboardExtractionError.unexpectedError,
      details: e.toString(),
    );
  }
}
