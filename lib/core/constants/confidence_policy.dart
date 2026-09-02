/// Classification bucket for any AI confidence score (detection or
/// extraction), per `07_CONFIDENCE_AND_CONFIRMATION.md`.
enum ConfidenceLevel {
  /// Trust the value for downstream processing without confirmation.
  high,

  /// Allow additional reasoning/validation; do not silently auto-fill.
  uncertain,

  /// Do not auto-fill a consequential field.
  low,
}

/// Configurable confidence thresholds shared by detection and AI-extraction
/// confidence handling, so thresholds live in one place instead of being
/// scattered through UI/service code.
class ConfidencePolicy {
  final double highConfidenceThreshold;
  final double uncertainThreshold;

  const ConfidencePolicy({
    this.highConfidenceThreshold = 0.90,
    this.uncertainThreshold = 0.60,
  }) : assert(uncertainThreshold <= highConfidenceThreshold);

  static const ConfidencePolicy standard = ConfidencePolicy();

  ConfidenceLevel classify(double confidence) {
    if (confidence >= highConfidenceThreshold) return ConfidenceLevel.high;
    if (confidence >= uncertainThreshold) return ConfidenceLevel.uncertain;
    return ConfidenceLevel.low;
  }
}
