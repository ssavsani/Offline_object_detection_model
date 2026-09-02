import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/constants/controlled_values.dart';
import '../../../../models/allowed_values.dart';
import '../../../../models/report_field.dart';
import '../../../../models/report_form.dart';
import '../../../../models/structured_form_patch.dart';
import '../../../../models/validation_result.dart';
import '../../../../services/form_patch_service.dart';

/// The result of running the deterministic rules engine and the RF-DETR ->
/// crop -> Qwen2-VL-2B-Instruct visual pipeline, merged into one patch — what
/// [DetectionScreen]'s `analyze` callback hands back to [ResultScreen] once
/// it resolves.
class AnalysisOutcome {
  final StructuredFormPatch patch;
  final List<ValidationIssue> issues;
  final bool malformed;

  const AnalysisOutcome({
    required this.patch,
    this.issues = const [],
    this.malformed = false,
  });
}

/// The editable "create/review report" form: shows [image] immediately,
/// runs [analyze] (Qwen2-VL image+text visual analysis) in the background
/// with an in-place loading state, then auto-fills every field it can once
/// analysis resolves — per the "Select/Take Image -> Qwen2-VL Analysis ->
/// Extract Details -> Auto-Fill All Fields -> User Reviews/Edits -> Submit"
/// flow. Every field stays editable at any time, including while analysis
/// is still running.
///
/// Fields Qwen2-VL has no visual signal for — [ReportField.location],
/// [ReportField.assignee], [ReportField.dueDate], [ReportField.disposition],
/// [ReportField.costRecovery] — are never auto-filled; they're left empty
/// (or, for disposition, a fixed manual default) rather than fabricated. See
/// `docs/OFFLINE_AI_IMPLEMENTATION.md`.
class ResultScreen extends StatefulWidget {
  final File image;
  final ReportForm initialForm;
  final Future<AnalysisOutcome> Function(void Function(String stage) onProgress) analyze;

  const ResultScreen({
    super.key,
    required this.image,
    required this.initialForm,
    required this.analyze,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static final AllowedValues _allowed = AppControlledValues.defaultValues;

  late ReportForm _form;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costRecoveryController = TextEditingController();

  String? _location;
  String? _issueType;
  String? _package;
  String? _severity;
  String? _assignee;
  String? _dueDate;
  String? _disposition;
  Set<ReportField> _needsConfirmation = {};

  bool _isLoading = true;
  String _stageLabel = 'Analyzing image…';
  List<ValidationIssue> _issues = const [];
  bool _malformed = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _form = widget.initialForm;
    _seedFieldsFrom(_form);
    // widget.analyze (ultimately DetectionAnalysisService.analyze) reports
    // its first progress stage synchronously, before any `await`. Calling
    // it directly here would run that synchronous setState() while this
    // widget is still mounting/building, which Flutter disallows — defer
    // to just after the first frame instead.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnalysis());
  }

  void _seedFieldsFrom(ReportForm form) {
    _titleController.text = form.title ?? '';
    _descriptionController.text = form.description ?? '';
    _costRecoveryController.text = form.costRecovery ?? '';
    _location = form.location;
    _issueType = form.issueType;
    _package = form.package;
    _severity = form.severity;
    _assignee = form.assignee;
    _dueDate = form.dueDate;
    _disposition = form.disposition ?? 'Identified';
    _needsConfirmation = {...form.needsConfirmation};
  }

  Future<void> _runAnalysis() async {
    if (!mounted) return;
    try {
      final outcome = await widget.analyze((stage) {
        if (mounted) setState(() => _stageLabel = stage);
      });
      final updated = FormPatchService.apply(widget.initialForm, outcome.patch);
      if (!mounted) return;
      setState(() {
        _form = updated;
        _seedFieldsFrom(updated);
        _issues = outcome.issues;
        _malformed = outcome.malformed;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Analysis failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _costRecoveryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review & Confirm')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Review and confirm details',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _buildImagePreview(),
            const SizedBox(height: 12),
            if (_isLoading) _buildLoadingBanner(),
            if (_loadError != null) ...[
              const SizedBox(height: 12),
              _buildErrorBanner(_loadError!),
            ],
            if (!_isLoading && _loadError == null) ...[
              if (_malformed) ...[
                _buildStatusBanner(
                  'The assistant response was invalid; some fields may be '
                  'incomplete. You can still fill them in manually.',
                ),
                const SizedBox(height: 12),
              ] else if (_issues.isNotEmpty) ...[
                _buildStatusBanner(_issues.map((i) => i.message).join(' ')),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 4),
            _buildFieldPair(
              context,
              _buildTextField(
                label: 'Title',
                icon: Icons.title,
                controller: _titleController,
                field: ReportField.title,
              ),
              _buildDropdownField(
                label: 'Location',
                icon: Icons.location_on_outlined,
                value: _location,
                options: _allowed.locations,
                field: ReportField.location,
                onChanged: (v) => setState(() {
                  _location = v;
                  _needsConfirmation.remove(ReportField.location);
                }),
              ),
            ),
            _buildTextField(
              label: 'Description',
              icon: Icons.description_outlined,
              controller: _descriptionController,
              field: ReportField.description,
              maxLines: 4,
            ),
            _buildFieldPair(
              context,
              _buildDropdownField(
                label: 'Task Type',
                icon: Icons.category_outlined,
                value: _issueType,
                options: _allowed.issueTypes,
                field: ReportField.issueType,
                onChanged: (v) => setState(() {
                  _issueType = v;
                  _needsConfirmation.remove(ReportField.issueType);
                }),
              ),
              _buildDropdownField(
                label: 'Package',
                icon: Icons.build_outlined,
                value: _package,
                options: _allowed.packages,
                field: ReportField.package,
                onChanged: (v) => setState(() {
                  _package = v;
                  _needsConfirmation.remove(ReportField.package);
                }),
              ),
            ),
            _buildFieldPair(
              context,
              _buildDropdownField(
                label: 'Severity',
                icon: Icons.priority_high,
                value: _severity,
                options: AllowedValues.severities,
                field: ReportField.severity,
                onChanged: (v) => setState(() {
                  _severity = v;
                  _needsConfirmation.remove(ReportField.severity);
                }),
              ),
              _buildDropdownField(
                label: 'Assigned To',
                icon: Icons.person_outline,
                value: _assignee,
                options: _allowed.assignees,
                field: ReportField.assignee,
                onChanged: (v) => setState(() {
                  _assignee = v;
                  _needsConfirmation.remove(ReportField.assignee);
                }),
              ),
            ),
            _buildFieldPair(
              context,
              _buildDateField(),
              _buildDropdownField(
                label: 'Disposition',
                icon: Icons.checklist_outlined,
                value: _disposition,
                options: _allowed.dispositions,
                field: ReportField.disposition,
                onChanged: (v) => setState(() {
                  _disposition = v;
                  _needsConfirmation.remove(ReportField.disposition);
                }),
              ),
            ),
            _buildTextField(
              label: 'Cost Recovery (£)',
              icon: Icons.payments_outlined,
              controller: _costRecoveryController,
              field: ReportField.costRecovery,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _confirmAndSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Confirm & Save Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Image.file(widget.image, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildLoadingBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(minHeight: 4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_stageLabel, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: const TextStyle(color: Colors.orange)),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: const TextStyle(color: Colors.red)),
    );
  }

  /// On tablet widths, lays two related fields side by side instead of
  /// stacked — purely a layout change, each field keeps its own state and
  /// validation exactly as on phone.
  Widget _buildFieldPair(BuildContext context, Widget first, Widget second) {
    if (!Breakpoints.isTablet(context)) {
      return Column(children: [first, second]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 16),
        Expanded(child: second),
      ],
    );
  }

  Widget? _confirmationIcon(ReportField field) {
    if (!_needsConfirmation.contains(field)) return null;
    return const Tooltip(
      message: 'Please confirm this field',
      child: Icon(Icons.help_outline, color: Colors.orange),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required ReportField field,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (_) {
          if (_needsConfirmation.contains(field)) {
            setState(() => _needsConfirmation.remove(field));
          }
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: _confirmationIcon(field),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> options,
    required ReportField field,
    required ValueChanged<String?> onChanged,
  }) {
    final resolvedValue = (value != null && options.contains(value)) ? value : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: resolvedValue,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: _confirmationIcon(field),
        ),
        hint: const Text('Select…'),
        items: [
          for (final option in options) DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDateField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: _pickDueDate,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Due Date',
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: _confirmationIcon(ReportField.dueDate) ??
                const Icon(Icons.edit_calendar_outlined),
          ),
          child: Text(_dueDate ?? 'Select a date'),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final initial = _dueDate != null ? DateTime.tryParse(_dueDate!) ?? now : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _dueDate = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      _needsConfirmation.remove(ReportField.dueDate);
    });
  }

  void _confirmAndSave() {
    final costText = _costRecoveryController.text.trim();
    if (costText.isNotEmpty && double.tryParse(costText) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cost recovery must be a number.')),
      );
      return;
    }

    final finalForm = _form.copyWith(
      title: _titleController.text,
      description: _descriptionController.text,
      location: _location,
      issueType: _issueType,
      package: _package,
      severity: _severity,
      assignee: _assignee,
      dueDate: _dueDate,
      disposition: _disposition,
      costRecovery: _costRecoveryController.text,
      needsConfirmation: _needsConfirmation,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report confirmed (no persistence backend in this demo).')),
    );
    Navigator.of(context).pop(finalForm);
  }
}
