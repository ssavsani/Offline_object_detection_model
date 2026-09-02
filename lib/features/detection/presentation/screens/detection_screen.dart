import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/breakpoints.dart';
import '../../../../core/constants/controlled_values.dart';
import '../../../../models/allowed_values.dart';
import '../../../../models/capture_flow_state.dart';
import '../../../../models/detection_context.dart';
import '../../../../models/detection_result.dart';
import '../../../../models/report_field.dart';
import '../../../../models/report_form.dart';
import '../../../../models/structured_form_patch.dart';
import '../../../../models/validation_result.dart';
import '../../../../services/audio_recorder_service.dart';
import '../../../../services/detection_analysis_service.dart';
import '../../../../services/detection_context_adapter.dart';
import '../../../../services/detection_field_suggester.dart';
import '../../../../services/form_patch_service.dart';
import '../../../../services/onnx_detection_service.dart';
import '../../../../services/qwen2_vl_extraction_service.dart';
import '../../../../services/rules_engine.dart';
import '../../../../services/silence_detector_service.dart';
import '../../../../services/validation_service.dart';
import '../../../../services/vlm_model_provisioning_service.dart';
import '../../../../services/voice_transcription_service.dart';
import '../../../report/presentation/screens/result_screen.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/detection_list_view.dart';

enum _ModelStatus { loading, ready, error }

enum _VlmStatus { notDownloaded, downloading, ready, unavailable }

/// The app's single screen: capture/pick an image, review the existing
/// RF-DETR detection, then describe the issue by voice or text and analyze
/// — all in one place, per the unified-workflow requirement.
///
/// The voice/analyze steps run automatically, driven by
/// [CaptureFlowState]: once RF-DETR finds at least one detection, recording
/// starts on its own; live transcription fills the description box directly
/// (no separate preview label) while [SilenceDetectorService] watches the
/// raw PCM stream for ~2s of continuous silence, at which point recording
/// stops and Analyze fires automatically. The mic and Analyze controls stay
/// visible throughout as manual retry/fallback paths (permission denied,
/// no speech detected, an early manual stop) — nothing here is a dead end.
/// Tapping "Analyze" opens [ResultScreen] immediately (image already
/// visible) and hands it an `analyze` callback; the actual RF-DETR -> crop
/// -> Qwen2-VL work runs in the background while that screen shows its own
/// loading state.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  final _detectionService = OnnxDetectionService();
  final _imagePicker = ImagePicker();
  final _textController = TextEditingController();
  final _audioRecorder = AudioRecorderService();
  final _voiceService = VoiceTranscriptionService();
  final _vlmProvisioning = VlmModelProvisioningService();
  late final _silenceDetector = SilenceDetectorService(
    onSilenceStart: _onSilenceStart,
    onSilenceCleared: _onSilenceCleared,
    onSilenceTimeout: _onSilenceTimeout,
  );
  Qwen2VlExtractionService? _vlmService;
  String? _vlmModelPath;
  String? _vlmMmprojPath;
  StreamSubscription<String>? _partialsSub;

  _ModelStatus _modelStatus = _ModelStatus.loading;
  String? _modelError;

  File? _selectedImage;
  DetectionResult? _result;
  String? _inferenceError;

  _VlmStatus _vlmStatus = _VlmStatus.notDownloaded;
  double _downloadProgress = 0;

  /// Guards against a stale async continuation (from a torn-down session)
  /// touching state after the user has already moved on to a new image —
  /// incremented once per [_pickImage] call; every async continuation
  /// below checks it hasn't changed before acting.
  int _sessionId = 0;
  CaptureFlowState _flowState = CaptureFlowState.idle;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _checkVlmAvailability();
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

  Future<void> _checkVlmAvailability() async {
    final downloaded = await _vlmProvisioning.isModelDownloaded();
    if (!mounted) return;
    if (downloaded) {
      _vlmModelPath = await _vlmProvisioning.modelPath;
      _vlmMmprojPath = await _vlmProvisioning.mmprojPath;
      _vlmService ??= Qwen2VlExtractionService();
    }
    setState(() => _vlmStatus = downloaded ? _VlmStatus.ready : _VlmStatus.notDownloaded);
  }

  Future<void> _downloadVlmModel() async {
    setState(() {
      _vlmStatus = _VlmStatus.downloading;
      _downloadProgress = 0;
      _actionError = null;
    });
    try {
      await for (final progress in _vlmProvisioning.download()) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress);
      }
      _vlmModelPath = await _vlmProvisioning.modelPath;
      _vlmMmprojPath = await _vlmProvisioning.mmprojPath;
      _vlmService ??= Qwen2VlExtractionService();
      if (!mounted) return;
      setState(() => _vlmStatus = _VlmStatus.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vlmStatus = _VlmStatus.unavailable;
        _actionError = 'Model download failed: $e';
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

      // A new image can arrive mid-recording or mid-analysis (Camera/
      // Gallery stay tappable throughout) — tear down whatever the
      // previous session had in flight before starting the new one, and
      // bump the session id so any still-pending async work from the old
      // session becomes a no-op when it resumes.
      await _teardownActiveSession();
      final sessionId = ++_sessionId;

      setState(() {
        _selectedImage = File(picked.path);
        _result = null;
        _inferenceError = null;
        _actionError = null;
        _flowState = CaptureFlowState.idle;
        _textController.clear();
      });
      await _runDetection(sessionId);
    } catch (e) {
      setState(() => _inferenceError = 'Failed to pick image: $e');
    }
  }

  /// Cancels any active recording/silence-detection/transcription for the
  /// current session, best-effort. Safe to call when nothing is active.
  Future<void> _teardownActiveSession() async {
    await _silenceDetector.cancel();
    await _partialsSub?.cancel();
    _partialsSub = null;
    if (_flowState == CaptureFlowState.recording ||
        _flowState == CaptureFlowState.silenceCountdown ||
        _flowState == CaptureFlowState.finalizingTranscript) {
      try {
        await _voiceService.stopLiveSession();
      } catch (_) {
        // Best-effort teardown only — the session is being discarded.
      }
      try {
        await _audioRecorder.stop();
      } catch (_) {
        // Best-effort teardown only — the session is being discarded.
      }
    }
  }

  Future<void> _runDetection(int sessionId) async {
    final image = _selectedImage;
    if (image == null || _modelStatus != _ModelStatus.ready) return;
    if (sessionId != _sessionId) return;

    setState(() {
      _inferenceError = null;
      _flowState = CaptureFlowState.detectingObjects;
    });

    try {
      final result = await _detectionService.detect(image);
      if (sessionId != _sessionId) return;
      setState(() => _result = result);
      if (result.detections.isNotEmpty) {
        setState(() => _flowState = CaptureFlowState.objectDetected);
        await _beginAutoVoiceCapture(sessionId);
      } else {
        setState(() => _flowState = CaptureFlowState.idle);
      }
    } catch (e) {
      if (sessionId != _sessionId) return;
      setState(() {
        _inferenceError = 'Inference failed: $e';
        _flowState = CaptureFlowState.error;
      });
    }
  }

  /// Starts recording automatically once an object has been detected.
  /// Every failure path here sets [CaptureFlowState.error] rather than
  /// leaving the UI stuck — the mic and Analyze buttons stay usable so the
  /// user always has a manual way forward.
  Future<void> _beginAutoVoiceCapture(int sessionId) async {
    if (sessionId != _sessionId) return;
    setState(() => _actionError = null);

    final bool hasPermission;
    try {
      hasPermission = await _audioRecorder.hasPermission();
    } catch (e) {
      if (sessionId != _sessionId) return;
      setState(() {
        _actionError = 'Could not check microphone permission: $e';
        _flowState = CaptureFlowState.error;
      });
      return;
    }
    if (sessionId != _sessionId) return;
    if (!hasPermission) {
      setState(() {
        _actionError = 'Microphone permission is required for voice input.';
        _flowState = CaptureFlowState.error;
      });
      return;
    }

    try {
      final pcmStream = await _audioRecorder.startStream();
      if (sessionId != _sessionId) return;
      final broadcastStream = pcmStream.asBroadcastStream();

      // Whisper's live session must attach to the broadcast stream first:
      // asBroadcastStream() only starts pulling from the recorder once it
      // gets its first listener, and broadcast streams don't buffer for
      // late subscribers — attaching the silence detector before this
      // would risk it stealing that first-listener slot and Whisper
      // silently missing the opening of the audio.
      final partials = await _voiceService.startLiveSession(broadcastStream);
      if (sessionId != _sessionId) return;

      _textController.clear();
      setState(() => _flowState = CaptureFlowState.recording);

      _partialsSub = partials.listen(
        (text) {
          if (!mounted || sessionId != _sessionId) return;
          // Each event is a full replacement transcript, not a delta, so
          // a plain assignment can never duplicate words.
          _textController.text = text;
        },
        onError: (Object e) {
          if (!mounted || sessionId != _sessionId) return;
          setState(() {
            _actionError = 'Transcription error: $e';
            _flowState = CaptureFlowState.error;
          });
        },
      );
      _silenceDetector.listen(broadcastStream);
    } catch (e) {
      if (sessionId != _sessionId) return;
      setState(() {
        _actionError = 'Could not start recording: $e';
        _flowState = CaptureFlowState.error;
      });
    }
  }

  void _onSilenceStart() {
    if (!mounted) return;
    if (_flowState == CaptureFlowState.recording) {
      setState(() => _flowState = CaptureFlowState.silenceCountdown);
    }
  }

  void _onSilenceCleared() {
    if (!mounted) return;
    if (_flowState == CaptureFlowState.silenceCountdown) {
      setState(() => _flowState = CaptureFlowState.recording);
    }
  }

  void _onSilenceTimeout() {
    if (!mounted) return;
    unawaited(_finalizeRecording(_sessionId, autoAnalyze: true));
  }

  /// Stops recording/transcription and resolves the final transcript —
  /// invoked either by [_onSilenceTimeout] (2s of continuous silence) or
  /// by a manual tap on the mic/stop button as an early-stop safety valve.
  /// Guarded so a near-simultaneous timeout + manual tap can't both run:
  /// the state check and transition happen synchronously, before any
  /// `await`, so only the first caller passes.
  Future<void> _finalizeRecording(int sessionId, {required bool autoAnalyze}) async {
    if (sessionId != _sessionId) return;
    if (_flowState != CaptureFlowState.recording &&
        _flowState != CaptureFlowState.silenceCountdown) {
      return;
    }
    setState(() => _flowState = CaptureFlowState.finalizingTranscript);

    await _silenceDetector.cancel();
    await _partialsSub?.cancel();
    _partialsSub = null;
    if (sessionId != _sessionId) return;

    try {
      await _audioRecorder.stop();
      final finalText = await _voiceService.stopLiveSession();
      if (sessionId != _sessionId) return;

      if (finalText == null) {
        // Once ResultScreen opens there's no way back to speak the missed
        // description, so this stays a retryable error instead of silently
        // auto-analyzing on nothing — mic/Analyze remain usable.
        setState(() {
          _flowState = CaptureFlowState.error;
          _actionError = 'No speech detected — type a description or tap the mic to try again.';
        });
        return;
      }

      _textController.text = finalText;
      setState(() => _flowState = CaptureFlowState.idle);
      if (autoAnalyze) {
        await _analyze(sessionId);
      }
    } catch (e) {
      if (sessionId != _sessionId) return;
      setState(() {
        _flowState = CaptureFlowState.error;
        _actionError = 'Voice transcription failed: $e';
      });
    }
  }

  Future<void> _analyze(int sessionId) async {
    if (sessionId != _sessionId) return;
    if (_flowState == CaptureFlowState.analyzing || _flowState == CaptureFlowState.completed) {
      return;
    }
    final result = _result;
    final image = _selectedImage;
    if (result == null || image == null) return;

    setState(() {
      _actionError = null;
      _flowState = CaptureFlowState.analyzing;
    });

    try {
      final detectionContext = DetectionContextAdapter.fromDetectionResult(result);
      final allowedValues = AppControlledValues.defaultValues;
      final initialForm = FormPatchService.apply(
        ReportForm(sourceDetectionContext: detectionContext),
        DetectionFieldSuggester.suggest(detectionContext),
      );
      final userText = _textController.text;
      final vlmExtractor = _vlmStatus == _VlmStatus.ready ? _vlmService : null;
      final vlmModelPath = _vlmStatus == _VlmStatus.ready ? _vlmModelPath : null;
      final vlmMmprojPath = _vlmStatus == _VlmStatus.ready ? _vlmMmprojPath : null;

      if (!mounted || sessionId != _sessionId) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultScreen(
          image: image,
          initialForm: initialForm,
          analyze: (onProgress) => _runAnalysis(
            image: image,
            detectionContext: detectionContext,
            userText: userText,
            allowedValues: allowedValues,
            vlmExtractor: vlmExtractor,
            vlmModelPath: vlmModelPath,
            vlmMmprojPath: vlmMmprojPath,
            onProgress: onProgress,
          ),
        ),
      ));
      if (!mounted || sessionId != _sessionId) return;
      setState(() => _flowState = CaptureFlowState.completed);
    } catch (e) {
      if (!mounted || sessionId != _sessionId) return;
      setState(() {
        _actionError = 'Could not open the report screen: $e';
        _flowState = CaptureFlowState.error;
      });
    }
  }

  /// The actual RF-DETR -> crop -> Qwen2-VL-2B-Instruct (image + text)
  /// analysis, plus the deterministic rules engine (zero-AI, disjoint
  /// fields), merged into one patch. This is [ResultScreen]'s `analyze`
  /// callback — it keeps running here so it still has this screen's live
  /// VLM service/model paths, while the loading state it drives is shown on
  /// that screen.
  Future<AnalysisOutcome> _runAnalysis({
    required File image,
    required DetectionContext detectionContext,
    required String userText,
    required AllowedValues allowedValues,
    required Qwen2VlExtractionService? vlmExtractor,
    required String? vlmModelPath,
    required String? vlmMmprojPath,
    required void Function(String stage) onProgress,
  }) async {
    final fields = <ReportField, FieldPatch>{};
    final issues = <ValidationIssue>[];

    // Deterministic single-field commands (e.g. "Assign this to Mayur.")
    // — zero-AI, no image involved, touches a disjoint field set from the
    // visual analysis below.
    final rulesPatch = RulesEngine.tryMatch(userText);
    if (rulesPatch != null) {
      final rulesResult = ValidationService.validatePatch(rulesPatch, allowedValues);
      fields.addAll(rulesResult.patch.fields);
      issues.addAll(rulesResult.issues);
    }

    // RF-DETR detection -> crop -> Qwen2-VL-2B-Instruct (image + text
    // together) -> validated title/description/severity/issue_type/package.
    final analysisService = DetectionAnalysisService(
      vlmExtractor: vlmExtractor,
      modelPath: vlmModelPath,
      mmprojPath: vlmMmprojPath,
    );
    final analysisResult = await analysisService.analyze(
      image: image,
      context: detectionContext,
      userText: userText,
      allowedValues: allowedValues,
      onProgress: onProgress,
    );
    fields.addAll(analysisResult.patch.fields);
    issues.addAll(analysisResult.issues);

    return AnalysisOutcome(
      patch: StructuredFormPatch(fields: fields),
      issues: issues,
      malformed: analysisResult.malformed,
    );
  }

  @override
  void dispose() {
    _partialsSub?.cancel();
    unawaited(_silenceDetector.cancel());
    _detectionService.dispose();
    _textController.dispose();
    _audioRecorder.dispose();
    _voiceService.release();
    _vlmService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = Breakpoints.isTablet(context) && _selectedImage != null;
    return Scaffold(
      appBar: AppBar(title: const Text('RF-DETR Nano Object Detection')),
      body: SafeArea(
        child: isTablet ? _buildTabletBody() : _buildPhoneBody(),
      ),
    );
  }

  Widget _buildPhoneBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildModelStatusBanner(),
        const SizedBox(height: 12),
        _buildActionButtons(),
        const SizedBox(height: 16),
        if (_selectedImage != null) _buildImagePreview(),
        ..._buildDetectionStatusChildren(),
        if (_result != null && _flowState != CaptureFlowState.detectingObjects) ...[
          const SizedBox(height: 16),
          _buildResultSummary(_result!),
          const SizedBox(height: 8),
          DetectionListView(detections: _result!.detections),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _buildVlmStatusBanner(),
          const SizedBox(height: 12),
          _buildVoiceAndTextInput(),
          if (_actionError != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(_actionError!),
          ],
          const SizedBox(height: 12),
          _buildAnalyzeButton(),
        ],
      ],
    );
  }

  Widget _buildTabletBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelStatusBanner(),
          const SizedBox(height: 16),
          _buildActionButtons(tablet: true),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: ListView(
                    children: [
                      _buildImagePreview(),
                      ..._buildDetectionStatusChildren(),
                      if (_result != null && _flowState != CaptureFlowState.detectingObjects) ...[
                        const SizedBox(height: 16),
                        _buildResultSummary(_result!),
                        const SizedBox(height: 8),
                        DetectionListView(detections: _result!.detections),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: ListView(
                    children: [
                      if (_result != null && _flowState != CaptureFlowState.detectingObjects) ...[
                        _buildVlmStatusBanner(),
                        const SizedBox(height: 16),
                        _buildVoiceAndTextInput(tablet: true),
                        if (_actionError != null) ...[
                          const SizedBox(height: 12),
                          _buildErrorBanner(_actionError!),
                        ],
                        const SizedBox(height: 20),
                        _buildAnalyzeButton(tablet: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shared between phone/tablet layouts: the inference spinner and
  /// detection-error banner that sit directly under the image preview.
  List<Widget> _buildDetectionStatusChildren() {
    return [
      if (_flowState == CaptureFlowState.detectingObjects) ...[
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        const Center(child: Text('Running inference…')),
      ],
      if (_inferenceError != null) ...[
        const SizedBox(height: 16),
        _buildErrorBanner(_inferenceError!),
      ],
    ];
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

  Widget _buildActionButtons({bool tablet = false}) {
    final ready = _modelStatus == _ModelStatus.ready &&
        _flowState != CaptureFlowState.detectingObjects;
    final minHeight = tablet ? 56.0 : 40.0;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: ready ? () => _pickImage(ImageSource.camera) : null,
            style: ElevatedButton.styleFrom(minimumSize: Size(0, minHeight)),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: ready ? () => _pickImage(ImageSource.gallery) : null,
            style: ElevatedButton.styleFrom(minimumSize: Size(0, minHeight)),
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

  Widget _buildVlmStatusBanner() {
    switch (_vlmStatus) {
      case _VlmStatus.ready:
        return const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 16),
            SizedBox(width: 6),
            Text('Visual analysis model ready • offline', style: TextStyle(fontSize: 12)),
          ],
        );
      case _VlmStatus.notDownloaded:
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Detailed defect analysis needs the local vision model '
                '(~1.7GB, one-time download).',
                style: TextStyle(fontSize: 12),
              ),
            ),
            TextButton(onPressed: _downloadVlmModel, child: const Text('Download')),
          ],
        );
      case _VlmStatus.downloading:
        return Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Downloading model… ${(_downloadProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      case _VlmStatus.unavailable:
        return const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orange, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Visual analysis model unavailable.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
    }
  }

  /// The label shown next to "Describe the issue" for states where the
  /// user needs a clear, glanceable indicator of what's happening — states
  /// outside this set (idle/objectDetected-already-passed/error/completed)
  /// don't need one; the error banner or plain text box already says enough.
  String? _voiceStatusLabel() {
    switch (_flowState) {
      case CaptureFlowState.objectDetected:
        return 'Starting…';
      case CaptureFlowState.recording:
        return 'Listening… 🎙';
      case CaptureFlowState.silenceCountdown:
        return 'Pause detected…';
      case CaptureFlowState.finalizingTranscript:
        return 'Finishing transcription…';
      case CaptureFlowState.idle:
      case CaptureFlowState.detectingObjects:
      case CaptureFlowState.analyzing:
      case CaptureFlowState.completed:
      case CaptureFlowState.error:
        return null;
    }
  }

  Widget _buildVoiceAndTextInput({bool tablet = false}) {
    final isRecordingPhase = _flowState == CaptureFlowState.recording ||
        _flowState == CaptureFlowState.silenceCountdown;
    final isFinalizing = _flowState == CaptureFlowState.finalizingTranscript;
    final statusLabel = _voiceStatusLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Describe the issue', style: Theme.of(context).textTheme.titleSmall),
            if (statusLabel != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: isRecordingPhase ? Colors.red : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMicButton(tablet: tablet),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !isRecordingPhase && !isFinalizing,
                maxLines: tablet ? 4 : 2,
                style: tablet ? const TextStyle(fontSize: 16) : null,
                decoration: InputDecoration(
                  hintText: isRecordingPhase
                      ? 'Listening…'
                      : 'e.g. "There is a large crack near the window, '
                          'assign it to Mayur."',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The mic control: shows a spinner while finalizing, a red stop icon
  /// during recording/silence-countdown (a manual early-stop safety valve
  /// — reuses the same [_finalizeRecording] the silence timeout calls), or
  /// a plain mic icon otherwise, enabled whenever there's a detection
  /// result to describe and no pipeline step is actively in flight.
  Widget _buildMicButton({bool tablet = false}) {
    final iconSize = tablet ? 32.0 : 24.0;
    if (_flowState == CaptureFlowState.finalizingTranscript) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_flowState == CaptureFlowState.recording ||
        _flowState == CaptureFlowState.silenceCountdown) {
      return IconButton.filled(
        iconSize: iconSize,
        onPressed: () => _finalizeRecording(_sessionId, autoAnalyze: true),
        style: IconButton.styleFrom(backgroundColor: Colors.red),
        icon: const Icon(Icons.stop),
      );
    }
    final canRecord = _result != null &&
        _flowState != CaptureFlowState.detectingObjects &&
        _flowState != CaptureFlowState.analyzing &&
        _flowState != CaptureFlowState.completed;
    return IconButton.filled(
      iconSize: iconSize,
      onPressed: canRecord ? () => _beginAutoVoiceCapture(_sessionId) : null,
      icon: const Icon(Icons.mic),
    );
  }

  Widget _buildAnalyzeButton({bool tablet = false}) {
    final canAnalyze = _result != null &&
        _flowState != CaptureFlowState.detectingObjects &&
        _flowState != CaptureFlowState.recording &&
        _flowState != CaptureFlowState.silenceCountdown &&
        _flowState != CaptureFlowState.finalizingTranscript &&
        _flowState != CaptureFlowState.analyzing &&
        _flowState != CaptureFlowState.completed;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: canAnalyze ? () => _analyze(_sessionId) : null,
        style: FilledButton.styleFrom(minimumSize: Size(0, tablet ? 56 : 40)),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Analyze'),
      ),
    );
  }
}
