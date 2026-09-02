import '../core/constants/confidence_policy.dart';
import 'bounding_box.dart';

/// One detection inside a [DetectionContext], independent of which detector
/// model produced it.
class DetectionContextItem {
  final String object;
  final double confidence;
  final BoundingBox boundingBox;
  final ConfidenceLevel confidenceLevel;

  const DetectionContextItem({
    required this.object,
    required this.confidence,
    required this.boundingBox,
    required this.confidenceLevel,
  });

  Map<String, dynamic> toJson() => {
        'object': object,
        'confidence': double.parse(confidence.toStringAsFixed(4)),
        'bbox': [
          boundingBox.left,
          boundingBox.top,
          boundingBox.right,
          boundingBox.bottom,
        ],
      };
}

/// Stable, model-independent view of a detector's output, per
/// `02_DETECTION_CONTEXT.md`. Downstream AI code (intent router, LLM
/// extraction) depends only on this type, never on detector internals, so
/// the underlying detector can change without breaking the AI pipeline.
class DetectionContext {
  final int imageWidth;
  final int imageHeight;
  final List<DetectionContextItem> detections;

  const DetectionContext({
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
  });

  const DetectionContext.empty()
      : imageWidth = 0,
        imageHeight = 0,
        detections = const [];

  /// The highest-confidence detection, if any. Detector output is assumed
  /// pre-sorted by descending confidence (true of the existing RF-DETR
  /// decoder); this does not re-sort.
  DetectionContextItem? get best => detections.isEmpty ? null : detections.first;

  bool get hasHighConfidenceDetection =>
      detections.any((d) => d.confidenceLevel == ConfidenceLevel.high);

  Map<String, dynamic> toJson() => {
        'image': {'width': imageWidth, 'height': imageHeight},
        'detections': detections.map((d) => d.toJson()).toList(),
      };
}
