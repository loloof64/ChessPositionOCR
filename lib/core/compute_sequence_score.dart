import 'package:ml_linalg/matrix.dart';
import 'package:ml_linalg/vector.dart';

List<Vector> computeLineStrengths({
  required Matrix image,
  required List<int> lineIndices,
  required bool horizontal,
}) {
  return lineIndices.map((index) {
    final values = horizontal
        ? image.getRow(index).map((e) => e.abs()).toList()
        : image.getColumn(index).map((e) => e.abs()).toList();
    return Vector.fromList(values);
  }).toList();
}

/// Trims sequences based on the average L2 norm of their gradient values.
/// Removes any sequence whose average vector norm is below a threshold (e.g. 50.0).
void trimSequences({
  required List<List<int>> seqs,
  required List<List<Vector>> seqVals,
  double normThreshold = 50.0,
}) {
  assert(
    seqs.length == seqVals.length,
    'Each sequence must have value vectors',
  );

  final trimmedSeqs = <List<int>>[];
  final trimmedVals = <List<Vector>>[];

  for (int i = 0; i < seqs.length; i++) {
    final values = seqVals[i];
    if (values.isEmpty) continue;

    // Compute average L2 norm of vectors
    final avgNorm =
        values.map((v) => v.norm()).reduce((a, b) => a + b) / values.length;

    if (avgNorm >= normThreshold) {
      trimmedSeqs.add(seqs[i]);
      trimmedVals.add(values);
    }
  }

  // Clear and refill original lists
  seqs
    ..clear()
    ..addAll(trimmedSeqs);
  seqVals
    ..clear()
    ..addAll(trimmedVals);
}

/// Compute mean scores for sequences based on their Hough peak values.
///
/// Returns a List&lt;double&gt; of mean scores.
List<double> computeSequenceScores(List<Vector> seqVals) {
  return seqVals.map((v) => v.mean()).toList();
}

/// Find the sequence with the highest score.
///
/// Returns the index of the best sequence.
int findBestSequenceIndex(List<double> scores) {
  double maxScore = scores[0];
  int bestIndex = 0;
  for (int i = 1; i < scores.length; i++) {
    if (scores[i] > maxScore) {
      maxScore = scores[i];
      bestIndex = i;
    }
  }
  return bestIndex;
}
