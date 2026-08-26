import 'bounding_box.dart';

/// A single decoded RF-DETR detection: one class prediction with its box.
class Detection {
  final String className;
  final int classIndex;
  final double confidence;
  final BoundingBox boundingBox;

  const Detection({
    required this.className,
    required this.classIndex,
    required this.confidence,
    required this.boundingBox,
  });

  Map<String, dynamic> toJson() => {
        'class': className,
        'confidence': double.parse(confidence.toStringAsFixed(4)),
        'boundingBox': boundingBox.toJson(),
      };
}
