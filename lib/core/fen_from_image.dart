import 'package:chess_position_ocr/core/compute_sequence_score.dart';
import 'package:chess_position_ocr/core/logger.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import './detect_chessboard_corners.dart';
import './cropping_and_correlation.dart';
import './misc_utils.dart';

const defaultNoiseThreshold = 8000.0;

/// Main integrated predictFen function
Future<String?> predictFen(
  Uint8List memoryImage, {
  double noiseThreshold = defaultNoiseThreshold,
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

  final gxGy = tupleGradients(grayMatrix);
  final gx = gxGy.$1;
  final gy = gxGy.$2;

  final List<int> potLinesX = detectionResult['potLinesX'] as List<int>;
  final List<int> potLinesY = detectionResult['potLinesY'] as List<int>;

  // Step 2: Find all sequences of lines with equal spacing
  final sequencesX = getAllSequences(potLinesX);
  final sequencesY = getAllSequences(potLinesY);

  if (sequencesX.isEmpty || sequencesY.isEmpty) {
    throw 'No valid line sequences found';
  }

  // Pick best (longest) sequences
  final valsX = computeLineStrengths(
    image: gx,
    lineIndices: potLinesX,
    horizontal: true,
  );
  final valsY = computeLineStrengths(
    image: gy,
    lineIndices: potLinesY,
    horizontal: false,
  );

  // Build a lookup table from potLinesX value to index
  final Map<int, int> potXIndexMap = {
    for (int i = 0; i < potLinesX.length; i++) potLinesX[i]: i,
  };
  // Build a lookup table from potLinesY value to index
  final Map<int, int> potYIndexMap = {
    for (int i = 0; i < potLinesY.length; i++) potLinesY[i]: i,
  };

  logger.d(
    'Before trimming: ${sequencesX.length} sequences for ${valsX.length} values',
  );
  for (final seq in sequencesX) {
    final vals = seq.map((i) => valsX[sequencesX.indexOf(seq)][0]).toList();
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    logger.d('Avg: $avg');
  }

  trimSequences(
    seqs: sequencesX,
    seqVals: sequencesX.map((seq) {
      return seq
          .where((x) => potXIndexMap.containsKey(x))
          .map((x) => valsX[potXIndexMap[x]!])
          .toList();
    }).toList(),
  );
  trimSequences(
    seqs: sequencesY,
    seqVals: sequencesY.map((seq) {
      return seq
          .where((y) => potYIndexMap.containsKey(y))
          .map((y) => valsY[potXIndexMap[y]!])
          .toList();
    }).toList(),
  );

  //////////////////////////////////
  logger.d('After trimming: ${sequencesX.length} sequences remain');
  for (var seq in sequencesX) {
    logger.d(
      'Sequence length: ${seq.length}, values: ${seq.map((i) => potLinesX.contains(i)).toList()}',
    );
  }
  ////////////////////////////////////

  /////////////////////////////////////
  logger.d('After trimming: ${sequencesY.length} sequences remain');
  for (var seq in sequencesY) {
    logger.d(
      'Sequence length: ${seq.length}, values: ${seq.map((i) => potLinesY.contains(i)).toList()}',
    );
  }
  ////////////////////////////////////

  ////////////////////////////////////////////
  logger.i('seqs X: ${sequencesX.length}');
  logger.i('seqs Y: ${sequencesY.length}');
  logger.i('vals X: ${valsX.length}');
  logger.i('vals Y: ${valsY.length}');
  ////////////////////////////////////////////

  final scoresX = computeSequenceScores(valsX);
  final scoresY = computeSequenceScores(valsY);

  ////////////////////////////////////////////
  logger.i('Scores X: ${scoresX.length}');
  logger.i('Scores Y: ${scoresY.length}');
  ////////////////////////////////////////////

  final bestXIndex = findBestSequenceIndex(scoresX);
  final bestYIndex = findBestSequenceIndex(scoresY);

  final bestSeqX = sequencesX[bestXIndex];
  final bestSeqY = sequencesY[bestYIndex];

  //////////////////////////////////////////
  logger.i('Best seq X: $bestSeqX');
  logger.i('Best seq Y: $bestSeqY');
  ///////////////////////////////////////////

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
