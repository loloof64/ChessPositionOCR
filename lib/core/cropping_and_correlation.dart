import 'package:image/image.dart' as img;

/// Generate ideal chessboard kernel (64x64) with alternating +1/-1 blocks
img.Image generateChessboardKernel(int tileSize) {
  // Create one tile of size tileSize x tileSize with all ones
  final quad = img.Image(width: tileSize, height: tileSize);
  img.fill(quad, color: img.ColorRgb8(255, 255, 255));

  // Create positive and negative tiles
  final posTile = quad;
  final negTile = img.copyRotate(
    quad,
    angle: 180,
  ); // just a placeholder for negative tile
  img.fill(negTile, color: img.ColorRgb8(0, 0, 0)); // black tile for -1

  // Build 2x2 block of tiles: [pos, neg; neg, pos]
  final blockWidth = tileSize * 2;
  final blockHeight = tileSize * 2;
  final block = img.Image(width: blockWidth, height: blockHeight);
  img.fill(block, color: img.ColorRgb8(0, 0, 0)); // init to black

  // Place tiles
  img.compositeImage(block, posTile, dstX: 0, dstY: 0);
  img.compositeImage(block, negTile, dstX: tileSize, dstY: 0);
  img.compositeImage(block, negTile, dstX: 0, dstY: tileSize);
  img.compositeImage(block, posTile, dstX: tileSize, dstY: tileSize);

  // Tile the block 4x4 times to get 8x8 tiles (64x64 px)
  final kernelSize = tileSize * 8;
  final kernel = img.Image(width: kernelSize, height: kernelSize);

  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      img.compositeImage(
        kernel,
        block,
        dstX: x * blockWidth,
        dstY: y * blockHeight,
      );
    }
  }

  return kernel;
}

/// Normalize image pixels to double array [0..1]
List<double> normalizeImage(img.Image image) {
  final pixels = List<double>.filled(image.width * image.height, 0);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final c = image.getPixel(x, y);
      // grayscale: red channel
      final gray = c.r;
      pixels[y * image.width + x] = gray / 255.0;
    }
  }
  return pixels;
}

/// Compute dot product (correlation) between two normalized images
double imageCorrelation(List<double> a, List<double> b) {
  assert(a.length == b.length);
  double sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// Crop subimage from img.Image, given corners [top, left, bottom, right]
img.Image cropImage(img.Image source, List<int> corners) {
  int top = corners[0];
  int left = corners[1];
  int bottom = corners[2];
  int right = corners[3];
  int width = right - left;
  int height = bottom - top;

  // Clamp coordinates to image bounds
  top = top.clamp(0, source.height - 1);
  bottom = bottom.clamp(0, source.height);
  left = left.clamp(0, source.width - 1);
  right = right.clamp(0, source.width);

  return img.copyCrop(source, x: left, y: top, width: width, height: height);
}

/// Main loop to iterate over sub sequences, crop candidates, resize and compute correlation
/// Returns best corners for detected chessboard
List<int>? findBestCorners({
  required img.Image grayImage,
  required List<List<int>> subSeqsX,
  required List<List<int>> subSeqsY,
  required List<int> outerCorners,
  required double dy,
  required double dx,
}) {
  final tileSize = 8; // pixels per tile
  final kernel = generateChessboardKernel(tileSize);
  final normKernelPixels = normalizeImage(kernel);

  img.Image croppedGray = cropImage(grayImage, outerCorners);

  double? bestScore;
  List<int>? finalCorners;

  for (var seqX in subSeqsX) {
    for (var seqY in subSeqsY) {
      // Calculate sub corners relative to cropped image
      List<int> subCorners = [
        seqY[0] - outerCorners[0] - dy.toInt(),
        seqX[0] - outerCorners[1] - dx.toInt(),
        seqY.last - outerCorners[0] + dy.toInt(),
        seqX.last - outerCorners[1] + dx.toInt(),
      ];

      // Crop candidate subimage and resize to 64x64 pixels
      img.Image candidateCrop = cropImage(croppedGray, subCorners);
      img.Image resizedCandidate = img.copyResize(
        candidateCrop,
        width: 64,
        height: 64,
      );

      final normCandidatePixels = normalizeImage(resizedCandidate);

      // Compute correlation score (absolute value)
      final score = imageCorrelation(
        normKernelPixels,
        normCandidatePixels,
      ).abs();

      if (bestScore == null || score > bestScore) {
        bestScore = score;
        finalCorners = [
          subCorners[0] + outerCorners[0],
          subCorners[1] + outerCorners[1],
          subCorners[2] + outerCorners[0],
          subCorners[3] + outerCorners[1],
        ];
      }
    }
  }

  return finalCorners;
}
