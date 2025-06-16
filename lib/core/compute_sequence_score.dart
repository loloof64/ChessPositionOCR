import 'package:ml_linalg/vector.dart';

/// Trim sequences to length 7–9 by removing weakest edges based on scores.
///
/// seqs: List of sequences (List&lt;int&gt;)
/// seqVals: List of corresponding scores (List&lt;Vector&gt;)
///
/// Returns trimmed sequences and their trimmed scores.
void trimSequences({
  required List<List<int>> seqs,
  required List<Vector> seqVals,
  int minLen = 7,
  int maxLen = 9,
}) {
  for (int i = 0; i < seqs.length; i++) {
    var seq = seqs[i];
    var vals = seqVals[i];

    // While longer than maxLen, remove the weaker edge
    while (seq.length > maxLen) {
      if (vals[0] > vals[vals.length - 1]) {
        seq = seq.sublist(0, seq.length - 1);
        vals = Vector.fromList(vals.toList().sublist(0, vals.length - 1));
      } else {
        seq = seq.sublist(1);
        vals = Vector.fromList(vals.toList().sublist(1));
      }
    }
    seqs[i] = seq;
    seqVals[i] = vals;
  }
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
