import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../core/constants/confidence_policy.dart';
import '../core/constants/crop_config.dart';
import '../models/allowed_values.dart';
import '../models/detection_context.dart';
import '../models/structured_form_patch.dart';
import '../models/validation_result.dart';
import 'detection_selector.dart';
import 'image_cropper.dart';
import 'validation_service.dart';
import 'vlm_extractor.dart';

/// Ties detection selection, original-image cropping, Qwen2-VL extraction,
/// and response validation into the single entry point the UI calls for
/// visual defect analysis — the image+text analog of the (removed)
/// text-only AI orchestration. Never throws: every failure mode (no
/// detection, low confidence, bad bbox, unavailable model, inference
/// failure, malformed response) resolves to a safe [ValidationResult]
/// instead, so the caller never needs its own try/catch around this.
class DetectionAnalysisService {
  DetectionAnalysisService({
    this.vlmExtractor,
    this.modelPath,
    this.mmprojPath,
    this.confidencePolicy = ConfidencePolicy.standard,
    this.cropConfig = CropConfig.standard,
  });

  /// Null when the local VLM runtime/model isn't available yet (e.g. not
  /// downloaded) — analysis then fails safely into confirmation instead of
  /// attempting any other source.
  final VlmExtractor? vlmExtractor;
  final String? modelPath;
  final String? mmprojPath;
  final ConfidencePolicy confidencePolicy;
  final CropConfig cropConfig;

  Future<ValidationResult> analyze({
    required File image,
    required DetectionContext context,
    required String userText,
    required AllowedValues allowedValues,
    void Function(String stage)? onProgress,
  }) async {
    onProgress?.call('Identifying defect…');
    final selected = DetectionSelector.select(context, userText);
    if (selected == null) {
      return _needsConfirmation('No detection available to analyze.');
    }

    final confidenceLevel = confidencePolicy.classify(selected.confidence);
    if (confidenceLevel == ConfidenceLevel.low) {
      // Per the confidence-handling spec: do not confidently report a
      // defect off a low-confidence detection. Detector confidence and
      // VLM-derived information are kept conceptually separate — this
      // never even calls the VLM.
      return ValidationResult(
        patch: StructuredFormPatch.empty,
        issues: [
          ValidationIssue(
            type: ValidationIssueType.lowConfidence,
            message: 'Detection confidence '
                '(${(selected.confidence * 100).toStringAsFixed(0)}%) is too '
                'low to confidently report a defect.',
          ),
        ],
      );
    }

    onProgress?.call('Preparing detected area…');
    final cropStopwatch = Stopwatch()..start();
    final Uint8List cropBytes;
    try {
      cropBytes = ImageCropper.crop(image, selected.boundingBox, config: cropConfig);
    } on FormatException catch (e, stackTrace) {
      developer.log(
        'Crop failed',
        name: 'DetectionAnalysisService',
        error: e,
        stackTrace: stackTrace,
      );
      return _needsConfirmation('Could not crop the detected region: ${e.message}');
    }
    developer.log(
      'Crop completed in ${cropStopwatch.elapsedMilliseconds}ms',
      name: 'DetectionAnalysisService',
    );

    final extractor = vlmExtractor;
    final model = modelPath;
    final mmproj = mmprojPath;
    if (extractor == null || model == null || mmproj == null) {
      return _needsConfirmation(
        'Local vision-language model is not available; please enter details manually.',
      );
    }

    onProgress?.call('Generating result…');
    final vlmStopwatch = Stopwatch()..start();
    final String raw;
    try {
      raw = await extractor.extract(
        modelPath: model,
        mmprojPath: mmproj,
        imageBytes: cropBytes,
        label: selected.object,
        userText: userText,
        allowedValues: allowedValues,
      );
    } catch (e, stackTrace) {
      // Logged (not swallowed), same as the removed text-LLM path: find
      // real root causes rather than masking failures, while still
      // failing safely for the UI.
      developer.log(
        'VLM extraction failed',
        name: 'DetectionAnalysisService',
        error: e,
        stackTrace: stackTrace,
      );
      return _needsConfirmation('Visual analysis failed: $e');
    }
    developer.log(
      'VLM inference completed in ${vlmStopwatch.elapsedMilliseconds}ms',
      name: 'DetectionAnalysisService',
    );

    final result = ValidationService.validateVlmOutput(raw, allowedValues);

    if (confidenceLevel == ConfidenceLevel.uncertain) {
      // Spec: medium confidence still runs the crop+VLM, but the result
      // must be marked uncertain rather than presented as trusted.
      return ValidationResult(
        patch: result.patch,
        malformed: result.malformed,
        issues: [
          ...result.issues,
          const ValidationIssue(
            type: ValidationIssueType.lowConfidence,
            message: 'Detection confidence is moderate; please verify this result.',
          ),
        ],
      );
    }

    return result;
  }

  ValidationResult _needsConfirmation(String message) => ValidationResult(
        patch: StructuredFormPatch.empty,
        issues: [
          ValidationIssue(
            type: ValidationIssueType.needsConfirmation,
            message: message,
          ),
        ],
      );
}
