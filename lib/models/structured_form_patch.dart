import 'report_field.dart';

/// A proposed update to one [ReportField].
///
/// `value == null` with `needsConfirmation == true` means "the source was
/// uncertain about this field" — it must never overwrite an existing form
/// value; it only flags the field for user confirmation.
class FieldPatch {
  final String? value;
  final bool needsConfirmation;

  const FieldPatch(this.value) : needsConfirmation = false;

  const FieldPatch.needsConfirmation()
      : value = null,
        needsConfirmation = true;
}

/// A sparse patch onto [ReportForm], per `08_FORM_INTEGRATION.md`: only
/// fields present in [fields] are touched when applied. A field absent from
/// this map must leave the corresponding form field untouched.
class StructuredFormPatch {
  final Map<ReportField, FieldPatch> fields;

  const StructuredFormPatch({this.fields = const {}});

  static const empty = StructuredFormPatch();

  bool get isEmpty => fields.isEmpty;

  Map<String, dynamic> toJson() => {
        for (final entry in fields.entries)
          entry.key.name: entry.value.needsConfirmation
              ? 'needs_confirmation'
              : entry.value.value,
      };
}
