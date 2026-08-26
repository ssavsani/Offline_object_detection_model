import 'detection.dart';

/// Full result of running detection on one image: source image size plus
/// every detection above the confidence threshold.
class DetectionResult {
  final int imageWidth;
  final int imageHeight;
  final List<Detection> detections;
  final int inferenceTimeMs;

  const DetectionResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
    required this.inferenceTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'image': {'width': imageWidth, 'height': imageHeight},
        'inferenceTimeMs': inferenceTimeMs,
        'detections': detections.map((d) => d.toJson()).toList(),
      };
}
