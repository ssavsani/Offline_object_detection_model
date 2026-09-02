import 'report_field.dart';

/// The application's real lists of controlled values, per
/// `06_CONTROLLED_FIELDS.md`. The LLM/rules layer may only select values
/// present here; anything else must be rejected rather than persisted.
class AllowedValues {
  final List<String> issueTypes;
  final List<String> locations;
  final List<String> assignees;
  final List<String> packages;
  final List<String> dispositions;

  /// Fixed per the Qwen2-VL structured-response contract (section 10 of the
  /// implementation spec): only "Low"/"Medium"/"High" are ever accepted.
  /// Not app-configurable data like the other lists, but exposed here too so
  /// severity flows through the exact same controlled-value checks in
  /// [ValidationService] as `issue_type`/`location`/`assign`/`package`.
  static const List<String> severities = ['Low', 'Medium', 'High'];

  const AllowedValues({
    required this.issueTypes,
    required this.locations,
    required this.assignees,
    required this.packages,
    required this.dispositions,
  });

  List<String> forField(ReportField field) {
    switch (field) {
      case ReportField.issueType:
        return issueTypes;
      case ReportField.location:
        return locations;
      case ReportField.assignee:
        return assignees;
      case ReportField.severity:
        return severities;
      case ReportField.package:
        return packages;
      case ReportField.disposition:
        return dispositions;
      case ReportField.title:
      case ReportField.description:
      case ReportField.dueDate:
      case ReportField.costRecovery:
        return const [];
    }
  }

  /// Whether [field] is a controlled field (must be validated against a
  /// fixed list) as opposed to free text.
  bool isControlled(ReportField field) =>
      field == ReportField.issueType ||
      field == ReportField.location ||
      field == ReportField.assignee ||
      field == ReportField.severity ||
      field == ReportField.package ||
      field == ReportField.disposition;

  bool isAllowed(ReportField field, String value) =>
      canonicalValue(field, value) != null;

  /// Returns the canonical (correctly-cased) allowed value matching [value]
  /// case-insensitively, or null if none match. Small local models are
  /// prompted with the exact allowed vocabulary but don't always reproduce
  /// its casing exactly (e.g. "civil" instead of "Civil") — matching
  /// case-insensitively and always storing the canonical form keeps
  /// downstream data consistent regardless of what casing the source used.
  String? canonicalValue(ReportField field, String value) {
    final normalized = value.trim().toLowerCase();
    for (final candidate in forField(field)) {
      if (candidate.toLowerCase() == normalized) return candidate;
    }
    return null;
  }
}
