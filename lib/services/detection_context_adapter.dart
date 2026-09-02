import '../core/constants/confidence_policy.dart';
import '../models/detection_context.dart';
import '../models/detection_result.dart';

/// Adapts the existing RF-DETR [DetectionResult] into the detector-independent
/// [DetectionContext] the AI pipeline depends on. This is the only place the
/// AI layer is allowed to touch detector-specific types — everything
/// downstream (rules, router, LLM extraction) depends on [DetectionContext]
/// only, per `02_DETECTION_CONTEXT.md`. It does not modify or re-run
/// detection; the existing detector behavior is unchanged.
class DetectionContextAdapter {
  DetectionContextAdapter._();

  static DetectionContext fromDetectionResult(
    DetectionResult result, {
    ConfidencePolicy policy = ConfidencePolicy.standard,
  }) {
    return DetectionContext(
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
      detections: result.detections
          .map((d) => DetectionContextItem(
                object: d.className,
                confidence: d.confidence,
                boundingBox: d.boundingBox,
                confidenceLevel: policy.classify(d.confidence),
              ))
          .toList(),
    );
  }
}
