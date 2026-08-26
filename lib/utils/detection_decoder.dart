import 'dart:math';

import '../models/bounding_box.dart';
import '../models/detection.dart';
import 'image_preprocessor.dart';

/// Decodes raw RF-DETR ONNX outputs into [Detection]s.
///
/// Confirmed against a Python onnxruntime run of the exact same model
/// (see `python/validate_inference.py`):
///  - `dets` (1, 300, 4): already-normalized center-based boxes
///    (cx, cy, w, h) in [0, 1] relative to the square model input. No extra
///    sigmoid is applied here — the exported graph already produces
///    normalized coordinates (verified by the decoded boxes lining up with
///    known synthetic-image geometry).
///  - `labels` (1, 300, num_classes): raw per-class logits. RF-DETR is
///    multi-label (independent sigmoid per class), not softmax, and this
///    export's last dimension exactly equals `num_classes` — there is no
///    extra "no-object" column to drop.
/// RF-DETR is NMS-free, so no non-max suppression is performed.
class DetectionDecoder {
  DetectionDecoder._();

  static double _sigmoid(double x) => 1.0 / (1.0 + exp(-x));

  static List<Detection> decode({
    required List<List<double>> dets,
    required List<List<double>> labels,
    required List<String> classNames,
    required double confidenceThreshold,
    required int inputSize,
    required LetterboxResult letterbox,
  }) {
    final results = <Detection>[];
    final numQueries = dets.length;

    for (int i = 0; i < numQueries; i++) {
      final logits = labels[i];
      int bestClassIdx = 0;
      double bestScore = _sigmoid(logits[0]);
      for (int c = 1; c < logits.length; c++) {
        final score = _sigmoid(logits[c]);
        if (score > bestScore) {
          bestScore = score;
          bestClassIdx = c;
        }
      }

      if (bestScore <= confidenceThreshold) continue;

      final box = dets[i];
      final cx = box[0] * inputSize;
      final cy = box[1] * inputSize;
      final w = box[2] * inputSize;
      final h = box[3] * inputSize;

      double x1 = cx - w / 2;
      double y1 = cy - h / 2;
      double x2 = cx + w / 2;
      double y2 = cy + h / 2;

      // Undo letterbox padding + scale to map back to original image pixels.
      x1 = (x1 - letterbox.padX) / letterbox.scale;
      y1 = (y1 - letterbox.padY) / letterbox.scale;
      x2 = (x2 - letterbox.padX) / letterbox.scale;
      y2 = (y2 - letterbox.padY) / letterbox.scale;

      x1 = x1.clamp(0, letterbox.originalWidth.toDouble());
      y1 = y1.clamp(0, letterbox.originalHeight.toDouble());
      x2 = x2.clamp(0, letterbox.originalWidth.toDouble());
      y2 = y2.clamp(0, letterbox.originalHeight.toDouble());

      results.add(Detection(
        className: bestClassIdx < classNames.length
            ? classNames[bestClassIdx]
            : 'class_$bestClassIdx',
        classIndex: bestClassIdx,
        confidence: bestScore,
        boundingBox: BoundingBox(left: x1, top: y1, right: x2, bottom: y2),
      ));
    }

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results;
  }
}
