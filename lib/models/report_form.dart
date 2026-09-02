import 'detection_context.dart';
import 'report_field.dart';

/// The minimal report/issue form this feature introduces so the AI pipeline
/// (image -> voice/text -> intent -> LLM -> validated fields) has a real
/// destination. There was no existing form/domain model in this app to
/// reuse (see `00_AGENT_INSTRUCTIONS.md` discovery notes) — this is a
/// deliberately small, in-memory model, not a persisted business entity.
class ReportForm {
  final String? title;
  final String? description;
  final String? issueType;
  final String? location;
  final String? assignee;

  /// One of "Low"/"Medium"/"High" once set — see [AllowedValues.severities].
  /// Populated only by the Qwen2-VL visual-analysis pipeline, never guessed
  /// from text alone.
  final String? severity;

  /// The building element/material affected (e.g. "Countertop", "Flooring").
  /// Populated only by the Qwen2-VL visual-analysis pipeline, same as
  /// [severity] — never guessed from text alone.
  final String? package;

  /// Manual-only: no AI source ever proposes a due date.
  final String? dueDate;

  /// Manual-only workflow status (e.g. "Identified"). No AI source ever
  /// proposes this — it's not derivable from an image or a text command.
  final String? disposition;

  /// Manual-only monetary figure. No AI source ever proposes this.
  final String? costRecovery;

  /// Fields flagged as needing user confirmation (low-confidence or
  /// ambiguous AI output). A field can be present here even while its value
  /// above is still null or still holds a prior user-entered value.
  final Set<ReportField> needsConfirmation;

  final DetectionContext? sourceDetectionContext;

  const ReportForm({
    this.title,
    this.description,
    this.issueType,
    this.location,
    this.assignee,
    this.severity,
    this.package,
    this.dueDate,
    this.disposition,
    this.costRecovery,
    this.needsConfirmation = const {},
    this.sourceDetectionContext,
  });

  const ReportForm.empty() : this();

  String? fieldValue(ReportField field) {
    switch (field) {
      case ReportField.title:
        return title;
      case ReportField.description:
        return description;
      case ReportField.issueType:
        return issueType;
      case ReportField.location:
        return location;
      case ReportField.assignee:
        return assignee;
      case ReportField.severity:
        return severity;
      case ReportField.package:
        return package;
      case ReportField.dueDate:
        return dueDate;
      case ReportField.disposition:
        return disposition;
      case ReportField.costRecovery:
        return costRecovery;
    }
  }

  ReportForm copyWith({
    String? title,
    String? description,
    String? issueType,
    String? location,
    String? assignee,
    String? severity,
    String? package,
    String? dueDate,
    String? disposition,
    String? costRecovery,
    Set<ReportField>? needsConfirmation,
    DetectionContext? sourceDetectionContext,
  }) {
    return ReportForm(
      title: title ?? this.title,
      description: description ?? this.description,
      issueType: issueType ?? this.issueType,
      location: location ?? this.location,
      assignee: assignee ?? this.assignee,
      severity: severity ?? this.severity,
      package: package ?? this.package,
      dueDate: dueDate ?? this.dueDate,
      disposition: disposition ?? this.disposition,
      costRecovery: costRecovery ?? this.costRecovery,
      needsConfirmation: needsConfirmation ?? this.needsConfirmation,
      sourceDetectionContext:
          sourceDetectionContext ?? this.sourceDetectionContext,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'issue_type': issueType,
        'location': location,
        'assign': assignee,
        'severity': severity,
        'package': package,
        'due_date': dueDate,
        'disposition': disposition,
        'cost_recovery': costRecovery,
        'needs_confirmation': needsConfirmation.map((f) => f.name).toList(),
      };
}
