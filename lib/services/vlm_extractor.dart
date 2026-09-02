import 'dart:typed_data';

import '../models/allowed_values.dart';

/// Seam between [DetectionAnalysisService] and the concrete local
/// vision-language-model runtime, so the orchestration layer (and its
/// tests) never need to load the real Qwen2-VL model. [imageBytes] and
/// [userText] must both actually reach the implementation — never just
/// [label] — per the "VLM must process image pixels together with text"
/// requirement; this is asserted directly against fakes of this interface
/// in tests. [allowedValues] is passed through so the implementation can
/// embed the real controlled-value vocabulary (locations, work packages,
/// assignees, …) in its prompt, letting the model map natural language to
/// the correct predefined values instead of guessing blind.
abstract class VlmExtractor {
  Future<String> extract({
    required String modelPath,
    required String mmprojPath,
    required Uint8List imageBytes,
    required String label,
    required String userText,
    required AllowedValues allowedValues,
  });
}
