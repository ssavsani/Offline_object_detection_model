import 'detection_result.dart';

/// Outcome of running detection on one image during a batch test run.
class BatchTestEntry {
  final String fileName;
  final DetectionResult? result;
  final String? error;

  const BatchTestEntry({required this.fileName, this.result, this.error});

  bool get succeeded => result != null;

  double get avgConfidence {
    final detections = result?.detections ?? const [];
    if (detections.isEmpty) return 0;
    final sum = detections.fold<double>(0, (s, d) => s + d.confidence);
    return sum / detections.length;
  }

  double get maxConfidence {
    final detections = result?.detections ?? const [];
    if (detections.isEmpty) return 0;
    return detections.map((d) => d.confidence).reduce((a, b) => a > b ? a : b);
  }
}
