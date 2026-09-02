import '../models/detection_context.dart';

/// Picks the one detection the Qwen2-VL stage should analyze out of
/// however many RF-DETR found, per the "Select relevant detection" spec:
/// highest confidence wins by default; among near-ties, prefer whichever
/// one the user's own text seems to be about. Deterministic and
/// intentionally simple — no LLM is used to pick a bounding box.
class DetectionSelector {
  DetectionSelector._();

  /// Detections within this much confidence of the top score are treated
  /// as "similar confidence" and become candidates for the text-match
  /// tie-break, instead of always taking the single highest score.
  static const double defaultSimilarConfidenceMargin = 0.05;

  /// Returns the selected detection, or `null` if [context] has none.
  static DetectionContextItem? select(
    DetectionContext context,
    String userText, {
    double similarConfidenceMargin = defaultSimilarConfidenceMargin,
  }) {
    final detections = context.detections;
    if (detections.isEmpty) return null;

    final maxConfidence =
        detections.map((d) => d.confidence).reduce((a, b) => a > b ? a : b);
    final candidates = detections
        .where((d) => maxConfidence - d.confidence <= similarConfidenceMargin)
        .toList();

    if (candidates.length == 1) return candidates.first;

    final text = userText.trim().toLowerCase();
    if (text.isNotEmpty) {
      for (final candidate in candidates) {
        if (text.contains(candidate.object.toLowerCase())) {
          return candidate;
        }
      }
    }

    // No text match among the near-ties (or no text at all): fall back to
    // the single highest-confidence detection. DetectionContext's own doc
    // states detector output is pre-sorted by descending confidence.
    return context.best;
  }
}
