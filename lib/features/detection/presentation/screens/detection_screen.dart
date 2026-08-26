import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../models/detection_result.dart';
import '../../../../services/onnx_detection_service.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/detection_list_view.dart';
import '../widgets/json_result_view.dart';

enum _ModelStatus { loading, ready, error }

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  final _detectionService = OnnxDetectionService();
  final _imagePicker = ImagePicker();

  _ModelStatus _modelStatus = _ModelStatus.loading;
  String? _modelError;

  File? _selectedImage;
  DetectionResult? _result;
  bool _isRunningInference = false;
  String? _inferenceError;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await _detectionService.initialize();
      setState(() => _modelStatus = _ModelStatus.ready);
    } catch (e) {
      setState(() {
        _modelStatus = _ModelStatus.error;
        _modelError = e.toString();
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        // Model input is 384x384; capping the picker output at 2x that
        // (768) keeps letterbox() strictly downsampling (no upscaling, so
        // detection confidence is unaffected) while cutting the pixel
        // count img.decodeImage/copyResize have to process by ~4x versus
        // the previous 1536 cap, reducing preprocessing time.
        maxWidth: 768,
        maxHeight: 768,
      );
      if (picked == null) return;

      setState(() {
        _selectedImage = File(picked.path);
        _result = null;
        _inferenceError = null;
      });
      await _runDetection();
    } catch (e) {
      setState(() => _inferenceError = 'Failed to pick image: $e');
    }
  }

  Future<void> _runDetection() async {
    final image = _selectedImage;
    if (image == null || _modelStatus != _ModelStatus.ready) return;

    setState(() {
      _isRunningInference = true;
      _inferenceError = null;
    });

    try {
      final result = await _detectionService.detect(image);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _inferenceError = 'Inference failed: $e');
    } finally {
      setState(() => _isRunningInference = false);
    }
  }

  @override
  void dispose() {
    _detectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RF-DETR Nano Object Detection')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildModelStatusBanner(),
            const SizedBox(height: 12),
            _buildActionButtons(),
            const SizedBox(height: 16),
            if (_selectedImage != null) _buildImagePreview(),
            if (_isRunningInference) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('Running inference…')),
            ],
            if (_inferenceError != null) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(_inferenceError!),
            ],
            if (_result != null && !_isRunningInference) ...[
              const SizedBox(height: 16),
              _buildResultSummary(_result!),
              const SizedBox(height: 8),
              DetectionListView(detections: _result!.detections),
              const SizedBox(height: 16),
              JsonResultView(json: _result!.toJson()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatusBanner() {
    switch (_modelStatus) {
      case _ModelStatus.loading:
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading RF-DETR Nano model…'),
          ],
        );
      case _ModelStatus.ready:
        final meta = _detectionService.metadata;
        return Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Model ready • ${meta.inputSize}x${meta.inputSize} • '
                '${meta.classNames.length} classes • offline',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      case _ModelStatus.error:
        return _buildErrorBanner('Failed to load model: $_modelError');
    }
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
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final ready = _modelStatus == _ModelStatus.ready && !_isRunningInference;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: ready ? () => _pickImage(ImageSource.camera) : null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: ready ? () => _pickImage(ImageSource.gallery) : null,
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    final result = _result;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: result != null
            ? result.imageWidth / result.imageHeight
            : 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_selectedImage!, fit: BoxFit.contain),
                if (result != null)
                  CustomPaint(
                    painter: BoundingBoxPainter(
                      detections: result.detections,
                      imageWidth: result.imageWidth,
                      imageHeight: result.imageHeight,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildResultSummary(DetectionResult result) {
    return Row(
      children: [
        Icon(
          result.detections.isEmpty ? Icons.info_outline : Icons.check_circle_outline,
          size: 18,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            result.detections.isEmpty
                ? 'No detection found'
                : '${result.detections.length} detection(s) found',
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.timer_outlined,
          size: 14,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        const SizedBox(width: 4),
        Text(
          'Detected in ${result.inferenceTimeMs} ms',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
