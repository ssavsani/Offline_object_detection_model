import '../models/report_field.dart';
import '../models/structured_form_patch.dart';

/// Deterministic single-field command matching, per `04_INTENT_ROUTER.md`.
///
/// Only recognizes input that is *entirely* a known command form (anchored
/// start/end) — e.g. "Assign this to Mayur." — so that a sentence merely
/// containing similar words alongside other information (e.g. "There is a
/// crack near the window and it needs to be assigned to Mayur.") does not
/// falsely match and instead falls through to the LLM path.
class RulesEngine {
  RulesEngine._();

  static final RegExp _assignPattern = RegExp(
    r'^assign\s+(?:this|it)?\s*to\s+([A-Za-z][\w\s]*?)\.?$',
    caseSensitive: false,
  );

  static final RegExp _issueTypePattern = RegExp(
    r'^(?:change|set)\s+issue\s*type\s+to\s+([A-Za-z][\w\s]*?)\.?$',
    caseSensitive: false,
  );

  static final RegExp _locationPattern = RegExp(
    r'^(?:change|set)\s+location\s+to\s+([A-Za-z0-9][\w\s]*?)\.?$',
    caseSensitive: false,
  );

  /// Returns a raw (unvalidated) single-field patch if [text] is entirely a
  /// recognized deterministic command, otherwise null.
  static StructuredFormPatch? tryMatch(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final assign = _assignPattern.firstMatch(trimmed);
    if (assign != null) {
      return StructuredFormPatch(fields: {
        ReportField.assignee: FieldPatch(assign.group(1)!.trim()),
      });
    }

    final issueType = _issueTypePattern.firstMatch(trimmed);
    if (issueType != null) {
      return StructuredFormPatch(fields: {
        ReportField.issueType: FieldPatch(issueType.group(1)!.trim()),
      });
    }

    final location = _locationPattern.firstMatch(trimmed);
    if (location != null) {
      return StructuredFormPatch(fields: {
        ReportField.location: FieldPatch(location.group(1)!.trim()),
      });
    }

    return null;
  }

  static bool isSimpleCommand(String text) => tryMatch(text) != null;
}
