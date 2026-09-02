import '../../models/allowed_values.dart';

/// Default/placeholder controlled-value lists for the report form.
///
/// This app had no existing controlled-value source (no real assignee/
/// location/issue-type list) to reuse — these are the illustrative values
/// from the feature docs themselves (`05_LLM_STRUCTURED_EXTRACTION.md`,
/// `06_CONTROLLED_FIELDS.md`), not invented business data. Replace with a
/// real application data source when one exists.
class AppControlledValues {
  AppControlledValues._();

  static const AllowedValues defaultValues = AllowedValues(
    issueTypes: ['Damaged', 'Missing', 'Incomplete', 'Maintenance', 'Safety'],
    locations: [
      'Floor 1',
      'Floor 2',
      'Floor 3',
      'Room 101',
      'Room 102',
      'Room 103',
    ],
    assignees: ['Shivani', 'Mayur', 'Dhaval', 'Chandresh'],
    packages: [
      'Civil',
      'Structural',
      'Electrical',
      'Plumbing',
      'Mechanical',
      'Finishing',
      'Countertop',
      'Flooring',
      'Doors/Windows',
    ],
    dispositions: ['Identified', 'In Progress', 'Resolved', 'Rejected'],
  );
}
