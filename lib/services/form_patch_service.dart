import '../models/report_field.dart';
import '../models/report_form.dart';
import '../models/structured_form_patch.dart';

/// Applies a validated [StructuredFormPatch] onto a [ReportForm], per
/// `08_FORM_INTEGRATION.md`. Only fields present in the patch are touched;
/// a field absent from the patch keeps whatever the user already entered.
/// A needs-confirmation entry never overwrites an existing value — it only
/// flags the field.
class FormPatchService {
  FormPatchService._();

  static ReportForm apply(ReportForm current, StructuredFormPatch patch) {
    String? title = current.title;
    String? description = current.description;
    String? issueType = current.issueType;
    String? location = current.location;
    String? assignee = current.assignee;
    String? severity = current.severity;
    String? package = current.package;
    String? dueDate = current.dueDate;
    String? disposition = current.disposition;
    String? costRecovery = current.costRecovery;
    final needsConfirmation = {...current.needsConfirmation};

    for (final entry in patch.fields.entries) {
      final field = entry.key;
      final incoming = entry.value;

      if (incoming.needsConfirmation) {
        needsConfirmation.add(field);
        continue;
      }

      final value = incoming.value;
      if (value == null) continue;

      needsConfirmation.remove(field);
      switch (field) {
        case ReportField.title:
          title = value;
        case ReportField.description:
          description = value;
        case ReportField.issueType:
          issueType = value;
        case ReportField.location:
          location = value;
        case ReportField.assignee:
          assignee = value;
        case ReportField.severity:
          severity = value;
        case ReportField.package:
          package = value;
        case ReportField.dueDate:
          dueDate = value;
        case ReportField.disposition:
          disposition = value;
        case ReportField.costRecovery:
          costRecovery = value;
      }
    }

    return current.copyWith(
      title: title,
      description: description,
      issueType: issueType,
      location: location,
      assignee: assignee,
      severity: severity,
      package: package,
      dueDate: dueDate,
      disposition: disposition,
      costRecovery: costRecovery,
      needsConfirmation: needsConfirmation,
    );
  }
}
