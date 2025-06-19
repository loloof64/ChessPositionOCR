import 'package:image/image.dart' as img;

/*
  chessboard_img_path = path to a chessboard image
  use_grayscale = true/false for whether to return tiles in grayscale

  Returns a list (length 64) of 32x32 image
 */
List<img.Image> getChessboardTiles(
  img.Image image, {
  bool useGrayscale = true,
}) {
  var imgData = getResizedChessboard(image);
  if (useGrayscale) {
    imgData = img.grayscale(imgData);
  }
  // 64 tiles in order from top-left to bottom-right (A8, B8, ..., G1, H1)
  List<img.Image> tiles = List<img.Image>.filled(
    64,
    img.Image(width: 32, height: 32, numChannels: 3),
  );
  for (int rank = 0; rank < 8; rank++) {
    for (int file = 0; file < 8; file++) {
      int sqI = rank * 8 + file;
      tiles[sqI] = extractChessboardTile(imgData, rank, file, useGrayscale);
    }
  }

  return tiles;
}

/*
  Returns a 256x256 image of a chessboard (32x32 per tile)
 */
img.Image getResizedChessboard(img.Image image) {
  img.Image rgbImage = img.bakeOrientation(
    image,
  ); // Correct orientation if needed
  // Copy pixels ignoring alpha
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;
      rgbImage.setPixelRgb(x, y, r, g, b);
    }
  }

  return img.copyResize(
    rgbImage,
    width: 256,
    height: 256,
    interpolation: img.Interpolation.linear, // same as PIL.Image.BILINEAR
  );
}

/// Extracts a 32x32 tile from a 256x256 chessboard image.
///
/// [chessboard256x256Img] is the source image (already loaded and resized).
/// [rank] and [file] specify the tile's position (0-based).
/// [useGrayscale] indicates whether to extract grayscale tiles.
/// Returns a 32x32 RGB image (img.Image).
img.Image extractChessboardTile(
  img.Image chessboard256x256Img,
  int rank,
  int file,
  bool useGrayscale,
) {
  // Create a new 32x32 RGB image (all pixels initialized to black).
  img.Image tile = img.Image(width: 32, height: 32, numChannels: 3);

  // Loop through each pixel in the tile.
  for (int i = 0; i < 32; i++) {
    for (int j = 0; j < 32; j++) {
      // Calculate the coordinates in the source image.
      int srcY = rank * 32 + i;
      int srcX = file * 32 + j;

      if (useGrayscale) {
        // If the source image is grayscale, copy the value to all RGB channels.
        // Assumes the grayscale value is stored in the least significant byte.
        num gray = chessboard256x256Img.getPixel(srcX, srcY).r;
        tile.setPixelRgb(j, i, gray, gray, gray);
      } else {
        // Otherwise, copy the RGB channels from the source image.
        img.Pixel pixel = chessboard256x256Img.getPixel(srcX, srcY);
        num r = pixel.r;
        num g = pixel.g;
        num b = pixel.b;
        tile.setPixelRgb(j, i, r, g, b);
      }
    }
  }
  return tile;
}
