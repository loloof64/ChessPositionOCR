import 'package:chess_position_ocr/core/compute_sequence_score.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:ml_linalg/vector.dart';

import './detect_chessboard_corners.dart';
import './cropping_and_correlation.dart';
import './misc_utils.dart';

/// Main integrated predictFen function
Future<String?> predictFen(
  Uint8List memoryImage, {
  double noiseThreshold = 8000.0,
}) async {
  final img.Image image = img.decodeImage(memoryImage)!;
  final img.Image grayImage = img.grayscale(image);
  // Convert img.Image to Matrix (grayscale) for detectChessboardCorners
  // Assuming detectChessboardCorners expects Matrix<double>
  final grayMatrix = imageToMatrix(grayImage);

  // Step 1: Rough chessboard corner detection
  final detectionResult = detectChessboardCorners(
    grayMatrix,
    noiseThreshold: noiseThreshold,
  );
  if (detectionResult == null) {
    throw 'Chessboard line detection failed';
  }

  final List<int> potLinesX = detectionResult['potLinesX'] as List<int>;
  final List<int> potLinesY = detectionResult['potLinesY'] as List<int>;

  // Step 2: Find all sequences of lines with equal spacing
  final sequencesX = getAllSequences(potLinesX);
  final sequencesY = getAllSequences(potLinesY);

  if (sequencesX.isEmpty || sequencesY.isEmpty) {
    throw 'No valid line sequences found';
  }

  // Pick best (longest) sequences
  final List<Vector> valsX = detectionResult['valsX'] as List<Vector>;
  final List<Vector> valsY = detectionResult['valsY'] as List<Vector>;

  trimSequences(seqs: sequencesX, seqVals: valsX);
  trimSequences(seqs: sequencesY, seqVals: valsY);

  final scoresX = computeSequenceScores(valsX);
  final scoresY = computeSequenceScores(valsY);

  final bestXIndex = findBestSequenceIndex(scoresX);
  final bestYIndex = findBestSequenceIndex(scoresY);

  final bestSeqX = sequencesX[bestXIndex];
  final bestSeqY = sequencesY[bestYIndex];

  // Step 3: Determine outer corners to crop image roughly
  final outerCorners = getOuterCorners(bestSeqX, bestSeqY);

  // Compute average spacing (dx, dy) between lines (approximate tile size)
  double dx = (bestSeqX.last - bestSeqX.first) / (bestSeqX.length - 1);
  double dy = (bestSeqY.last - bestSeqY.first) / (bestSeqY.length - 1);

  // Step 4: Refine corners using correlation (cropping_and_correlation logic)
  final refinedCorners = findBestCorners(
    grayImage: grayImage,
    subSeqsX: sequencesX,
    subSeqsY: sequencesY,
    outerCorners: outerCorners,
    dy: dy,
    dx: dx,
  );

  if (refinedCorners == null) {
    throw 'Corner refinement failed';
  }

  // Step 5: Crop and warp board using refinedCorners
  final croppedBoard = img.copyCrop(
    grayImage,
    x: refinedCorners[1], // left
    y: refinedCorners[0], // top
    width: refinedCorners[3] - refinedCorners[1],
    height: refinedCorners[2] - refinedCorners[0],
  );
  final warpedBoard = warpBoardToSquare(croppedBoard, refinedCorners);

  // Step 6: Extract 64 squares and predict pieces (you need to implement this)
  final squares = extractSquares(warpedBoard);
  final pieces = await Future.wait(squares.map(predictPieceFromSquare));

  // Step 7: Build FEN string from pieces
  final boardFen = buildFenBoard(pieces);

  return '$boardFen w - - 0 1';
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
