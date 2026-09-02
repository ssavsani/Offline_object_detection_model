/// The controlled/free-text fields on [ReportForm] that the AI pipeline is
/// allowed to propose updates for.
///
/// `dueDate`, `disposition`, and `costRecovery` are manual-only — nothing in
/// the AI pipeline ever proposes them since there's no visual or textual
/// signal for a due date, workflow status, or a monetary figure.
enum ReportField {
  title,
  description,
  issueType,
  location,
  assignee,
  severity,
  package,
  dueDate,
  disposition,
  costRecovery,
}
