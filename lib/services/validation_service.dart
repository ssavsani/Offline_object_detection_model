import 'dart:convert';

import '../models/allowed_values.dart';
import '../models/report_field.dart';
import '../models/structured_form_patch.dart';
import '../models/validation_result.dart';

/// Validates a raw (unvalidated) [StructuredFormPatch] — produced by either
/// `RulesEngine` or the Qwen2-VL extraction service — against the
/// application's controlled-value lists, per `06_CONTROLLED_FIELDS.md`.
/// Never trusts the source directly: an invalid controlled value is
/// downgraded to needs-confirmation rather than silently substituted or
/// dropped.
class ValidationService {
  ValidationService._();

  /// Decodes [raw] as a JSON object, tolerating the common ways a small
  /// local model wraps otherwise-valid JSON: markdown code fences, or a
  /// stray sentence before/after the object. Tries the raw text first;
  /// only if that fails does it fall back to the substring between the
  /// first `{` and the last `}`. Returns `null` (never throws) when no
  /// JSON object can be recovered at all — e.g. a reply that is prose with
  /// no JSON in it, which must still be treated as malformed, per the
  /// mandatory "AI response failure" test.
  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    Map<String, dynamic>? tryDecode(String text) {
      try {
        final decoded = jsonDecode(text);
        return decoded is Map<String, dynamic> ? decoded : null;
      } on FormatException {
        return null;
      }
    }

    final direct = tryDecode(raw.trim());
    if (direct != null) return direct;

    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return tryDecode(raw.substring(start, end + 1));
  }

  /// Parses and validates raw structured-AI-output JSON (shared shape used
  /// by both [ValidationService.validateVlmOutput] and any future
  /// structured-output source) in one pass: stage 1 (JSON parsing), stage
  /// 2/3 (type/field checks), then the same controlled-value stage as
  /// [validatePatch]. Malformed JSON (not parseable, or not a JSON object)
  /// fails safely with an empty patch rather than throwing, per
  /// `06_CONTROLLED_FIELDS.md`'s validation-stage list.
  static ValidationResult _validateStructuredOutput(
    String rawJson,
    AllowedValues allowed,
    Map<String, ReportField> keyToField,
  ) {
    final decoded = _decodeJsonObject(rawJson);
    if (decoded == null) {
      return const ValidationResult(patch: StructuredFormPatch.empty, malformed: true);
    }

    final fields = <ReportField, FieldPatch>{};
    final typeIssues = <ValidationIssue>[];

    for (final entry in decoded.entries) {
      final field = keyToField[entry.key];
      if (field == null) continue; // Unknown key: ignore, do not guess.

      final value = entry.value;
      if (value == null) {
        // Explicit null: the model marked this field uncertain.
        fields[field] = const FieldPatch.needsConfirmation();
      } else if (value is String) {
        fields[field] = FieldPatch(value);
      } else {
        typeIssues.add(ValidationIssue(
          field: field,
          type: ValidationIssueType.wrongType,
          message: 'Expected a string for ${field.name}, got ${value.runtimeType}.',
        ));
        fields[field] = const FieldPatch.needsConfirmation();
      }
    }

    final controlledValueResult =
        validatePatch(StructuredFormPatch(fields: fields), allowed);

    return ValidationResult(
      patch: controlledValueResult.patch,
      issues: [...typeIssues, ...controlledValueResult.issues],
    );
  }

  static const Map<String, ReportField> _vlmKeyToField = {
    'title': ReportField.title,
    'description': ReportField.description,
    'severity': ReportField.severity,
    'issue_type': ReportField.issueType,
    'package': ReportField.package,
    'workpackage': ReportField.package,
    'location': ReportField.location,
    'assign_to': ReportField.assignee,
  };

  /// Parses and validates Qwen2-VL's raw structured-output contract
  /// (`{"title": ..., "description": ..., "severity": ..., "issue_type":
  /// ..., "location": ..., "workpackage": ..., "assign_to": ...}`) via
  /// [_validateStructuredOutput]. `severity`, `issue_type`, `location`,
  /// `workpackage`/`package`, and `assign_to` are all controlled fields
  /// (see [AllowedValues]) so an out-of-list value is downgraded to
  /// needs-confirmation, and a recognized-but-differently-cased value is
  /// normalized to its canonical form, by the same controlled-value stage
  /// [validatePatch] already applies everywhere else. `workpackage` and
  /// `package` are accepted as synonyms for the same [ReportField.package]
  /// — the prompt only ever emits `workpackage`, but this keeps the older
  /// key working too.
  static ValidationResult validateVlmOutput(
    String rawJson,
    AllowedValues allowed,
  ) =>
      _validateStructuredOutput(rawJson, allowed, _vlmKeyToField);

  static ValidationResult validatePatch(
    StructuredFormPatch raw,
    AllowedValues allowed,
  ) {
    final sanitized = <ReportField, FieldPatch>{};
    final issues = <ValidationIssue>[];

    for (final entry in raw.fields.entries) {
      final field = entry.key;
      final incoming = entry.value;

      if (incoming.needsConfirmation) {
        sanitized[field] = incoming;
        continue;
      }

      final value = incoming.value?.trim();
      if (value == null || value.isEmpty) {
        // No usable value proposed for this field; leave it absent from the
        // sanitized patch rather than recording an issue.
        continue;
      }

      if (allowed.isControlled(field)) {
        final canonical = allowed.canonicalValue(field, value);
        if (canonical != null) {
          sanitized[field] = FieldPatch(canonical);
        } else {
          issues.add(ValidationIssue(
            field: field,
            type: ValidationIssueType.invalidControlledValue,
            message:
                '"$value" is not an allowed value for ${field.name}.',
          ));
          sanitized[field] = const FieldPatch.needsConfirmation();
        }
      } else {
        sanitized[field] = FieldPatch(value);
      }
    }

    return ValidationResult(
      patch: StructuredFormPatch(fields: sanitized),
      issues: issues,
    );
  }
}
