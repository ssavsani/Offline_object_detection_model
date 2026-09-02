import 'report_field.dart';
import 'structured_form_patch.dart';

enum ValidationIssueType {
  malformedJson,
  wrongType,
  invalidControlledValue,
  lowConfidence,
  needsConfirmation,
}

/// One rejected/flagged field (or whole-payload) issue, kept for
/// diagnostics/audit — never surfaced as if it were a trusted value.
class ValidationIssue {
  final ReportField? field;
  final ValidationIssueType type;
  final String message;

  const ValidationIssue({
    this.field,
    required this.type,
    required this.message,
  });
}

/// Outcome of running an AI-proposed patch through the validation pipeline
/// in `06_CONTROLLED_FIELDS.md`. [patch] is always safe to apply as-is:
/// invalid or uncertain fields have already been stripped down to
/// confirmation-only entries, never a substituted value.
class ValidationResult {
  final StructuredFormPatch patch;
  final List<ValidationIssue> issues;

  /// True only when the raw input could not be parsed as a JSON object at
  /// all (mandatory test: "malformed JSON").
  final bool malformed;

  const ValidationResult({
    required this.patch,
    this.issues = const [],
    this.malformed = false,
  });

  bool get hasIssues => malformed || issues.isNotEmpty;
}
