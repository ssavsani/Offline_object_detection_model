import '../core/constants/confidence_policy.dart';
import '../models/detection_context.dart';
import '../models/report_field.dart';
import '../models/structured_form_patch.dart';

/// Produces an initial, unvalidated form suggestion straight from detection
/// output, per `07_CONFIDENCE_AND_CONFIRMATION.md`: only a high-confidence
/// detection may propose a concrete field value ("Trust detection for
/// downstream processing"); anything in the uncertain/low band must come
/// back as needs-confirmation rather than a value someone could mistake for
/// a trusted one ("Do not auto-fill a consequential field").
class DetectionFieldSuggester {
  DetectionFieldSuggester._();

  static StructuredFormPatch suggest(DetectionContext context) {
    final best = context.best;
    if (best == null) return StructuredFormPatch.empty;

    final FieldPatch descriptionPatch;
    switch (best.confidenceLevel) {
      case ConfidenceLevel.high:
        descriptionPatch = FieldPatch('Possible ${best.object} detected.');
      case ConfidenceLevel.uncertain:
      case ConfidenceLevel.low:
        descriptionPatch = const FieldPatch.needsConfirmation();
    }

    return StructuredFormPatch(
      fields: {ReportField.description: descriptionPatch},
    );
  }
}
