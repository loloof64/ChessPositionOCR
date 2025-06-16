// Dart implementation (partial) of detect_chessboard_corners using ml_linalg
// Focuses on gradient processing, signal filtering, and peak detection

import 'dart:math';
import 'package:ml_linalg/matrix.dart';
import 'package:ml_linalg/vector.dart';

/// Compute standard deviation of a Vector
double standardDeviation(Vector v) {
  final values = v.toList();
  final mean = values.reduce((a, b) => a + b) / values.length;
  final squaredDiffs = values.map((x) => pow(x - mean, 2)).toList();
  final variance = squaredDiffs.reduce((a, b) => a + b) / values.length;
  return sqrt(variance);
}

/// Compute 2D gradients gx, gy from a grayscale image represented as a Matrix
tupleGradients(Matrix image) {
  final rows = image.rowCount;
  final cols = image.columnCount;
  final gx = List.generate(rows, (i) => List.filled(cols, 0.0));
  final gy = List.generate(rows, (i) => List.filled(cols, 0.0));

  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      gx[i][j] =
          (j < cols - 1 ? image[i][j + 1] : image[i][j]) -
          (j > 0 ? image[i][j - 1] : image[i][j]);
      gy[i][j] =
          (i < rows - 1 ? image[i + 1][j] : image[i][j]) -
          (i > 0 ? image[i - 1][j] : image[i][j]);
    }
  }

  return (Matrix.fromList(gx), Matrix.fromList(gy));
}

/// Separate gradients into positive and negative parts
Matrix positivePart(Matrix m) => m.mapElements((e) => max(e, 0.0));
Matrix negativePart(Matrix m) => m.mapElements((e) => max(-e, 0.0));

/// 1D non-maximum suppression
Vector nonMaxSuppress1D(Vector v) {
  final n = v.length;
  final result = List<double>.filled(n, 0.0);
  for (int i = 1; i < n - 1; i++) {
    final prev = v[i - 1];
    final curr = v[i];
    final next = v[i + 1];
    if (curr > prev && curr > next) {
      result[i] = curr;
    }
  }
  return Vector.fromList(result);
}

/// Filter values below threshold
Vector thresholdSuppress(Vector v, double threshold) {
  return Vector.fromList(
    v.toList().map((val) => val >= threshold ? val : 0.0).toList(),
  );
}

/// Find indices of non-zero elements
List<int> whereNonZero(Vector v) {
  final result = <int>[];
  for (int i = 0; i < v.length; i++) {
    if (v[i] != 0.0) result.add(i);
  }
  return result;
}

/// Check if the signal is strong enough
bool isValidSignal(Vector houghX, Vector houghY, double threshold) {
  final stdX = standardDeviation(houghX);
  final stdY = standardDeviation(houghY);
  final normalizedStdX = stdX / houghX.length;
  final normalizedStdY = stdY / houghY.length;
  return min(normalizedStdX, normalizedStdY) >= threshold;
}

/// Partial conversion of detect_chessboard_corners
Map<String, dynamic>? detectChessboardCorners(
  Matrix grayImage, {
  double noiseThreshold = 8000.0,
}) {
  final (gx, gy) = tupleGradients(grayImage);
  final gxPos = positivePart(gx);
  final gxNeg = negativePart(gx);
  final gyPos = positivePart(gy);
  final gyNeg = negativePart(gy);

  final houghGx = Vector.fromList(
    List.generate(
      grayImage.rowCount,
      (i) => gxPos.getRow(i).sum() * gxNeg.getRow(i).sum(),
    ),
  );
  final houghGy = Vector.fromList(
    List.generate(
      grayImage.columnCount,
      (j) => gyPos.getColumn(j).sum() * gyNeg.getColumn(j).sum(),
    ),
  );

  if (!isValidSignal(houghGx, houghGy, noiseThreshold)) {
    return null;
  }

  final normHoughGx = nonMaxSuppress1D(houghGx) / houghGx.max();
  final normHoughGy = nonMaxSuppress1D(houghGy) / houghGy.max();

  final filteredHoughGx = thresholdSuppress(normHoughGx, 0.2);
  final filteredHoughGy = thresholdSuppress(normHoughGy, 0.2);

  final potLinesX = whereNonZero(filteredHoughGx);
  final potLinesY = whereNonZero(filteredHoughGy);

  return {
    'potLinesX': potLinesX,
    'potLinesY': potLinesY,
    'houghGx': houghGx,
    'houghGy': houghGy,
  };
}

/// Finds all sequences of length 7 or more from sorted positions
/// that have roughly equal spacing (within a tolerance).
///
/// This mimics the Python _get_all_sequences function used to find
/// potential chessboard line sequences.
///
/// Returns a list of sequences (each sequence is a List&lt;int&gt;).
List<List<int>> getAllSequences(
  List<int> sortedPositions, {
  int minLength = 7,
  double tolerance = 3.0,
}) {
  final sequences = <List<int>>[];

  for (int start = 0; start < sortedPositions.length; start++) {
    for (int end = start + minLength; end <= sortedPositions.length; end++) {
      final seq = sortedPositions.sublist(start, end);

      if (seq.length < minLength) continue;

      // Compute spacings (differences)
      final diffs = <int>[];
      for (int i = 1; i < seq.length; i++) {
        diffs.add(seq[i] - seq[i - 1]);
      }

      // Check if diffs are approximately equal within tolerance
      final maxDiff = diffs.reduce((a, b) => a > b ? a : b);
      final minDiff = diffs.reduce((a, b) => a < b ? a : b);

      if ((maxDiff - minDiff) <= tolerance) {
        sequences.add(seq);
      }
    }
  }

  return sequences;
}
