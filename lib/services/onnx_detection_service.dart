import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../core/constants/model_constants.dart';
import '../models/detection_result.dart';
import '../models/model_metadata.dart';
import '../utils/detection_decoder.dart';
import '../utils/image_preprocessor.dart';

/// Loads the bundled RF-DETR Nano ONNX model and runs fully-offline
/// detection on a local image file.
///
/// Owns the ONNX Runtime session lifecycle: [initialize] must be called
/// once before [detect], and [dispose] must be called when the service is
/// no longer needed to release native resources.
class OnnxDetectionService {
  OrtSession? _session;
  ModelMetadata? _metadata;
  bool _envInitialized = false;

  ModelMetadata get metadata {
    final m = _metadata;
    if (m == null) {
      throw StateError('OnnxDetectionService.initialize() was not called.');
    }
    return m;
  }

  bool get isReady => _session != null;

  Future<void> initialize() async {
    if (isReady) return;

    final metadataJson = jsonDecode(
      await rootBundle.loadString(ModelConstants.metadataAssetPath),
    ) as Map<String, dynamic>;
    final metadata = ModelMetadata.fromJson(metadataJson);

    if (!_envInitialized) {
      OrtEnv.instance.init();
      _envInitialized = true;
    }

    final modelBytes =
        (await rootBundle.load(metadata.onnxAssetPath)).buffer.asUint8List();

    OrtSession session;
    try {
      session = _createSession(modelBytes, useHardwareAcceleration: true);
    } catch (_) {
      // NNAPI/CoreML register successfully but can still reject this
      // model's graph (e.g. RF-DETR's transformer/attention ops) once
      // session creation actually tries to build it, so that failure only
      // surfaces here rather than from appendNnapiProvider/appendCoreMLProvider
      // above. Retry on XNNPACK/CPU, which supports the full ONNX op set.
      session = _createSession(modelBytes, useHardwareAcceleration: false);
    }

    _metadata = metadata;
    _session = session;
  }

  OrtSession _createSession(
    Uint8List modelBytes, {
    required bool useHardwareAcceleration,
  }) {
    final sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );
    if (useHardwareAcceleration) {
      _appendAccelerationProviders(sessionOptions);
    } else {
      try {
        sessionOptions.appendXnnpackProvider();
      } catch (_) {
        // XNNPACK unavailable; ORT falls back to the default CPU provider.
      }
    }
    try {
      return OrtSession.fromBuffer(modelBytes, sessionOptions);
    } finally {
      sessionOptions.release();
    }
  }

  /// Registers hardware execution providers on a best-effort basis, falling
  /// back to XNNPACK's optimized CPU kernels and ultimately the default CPU
  /// provider if none are supported on this device. `appendXxxProvider`
  /// calls throw on failure, so each attempt is isolated with try/catch —
  /// a device lacking NNAPI/CoreML support must not block model loading.
  void _appendAccelerationProviders(OrtSessionOptions sessionOptions) {
    if (Platform.isAndroid) {
      try {
        sessionOptions.appendNnapiProvider(NnapiFlags.useFp16);
      } catch (_) {
        // NNAPI unavailable on this device; fall through to XNNPACK/CPU.
      }
    } else if (Platform.isIOS) {
      try {
        sessionOptions.appendCoreMLProvider(CoreMLFlags.enableOnSubgraph);
      } catch (_) {
        // CoreML unavailable on this device; fall through to XNNPACK/CPU.
      }
    }

    try {
      sessionOptions.appendXnnpackProvider();
    } catch (_) {
      // XNNPACK unavailable; ORT falls back to the default CPU provider.
    }
  }

  Future<DetectionResult> detect(File imageFile) async {
    final session = _session;
    final metadata = _metadata;
    if (session == null || metadata == null) {
      throw StateError('OnnxDetectionService.initialize() was not called.');
    }

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unable to decode the selected image.');
    }
    // EXIF orientation is not applied by decodeImage by default.
    final source = img.bakeOrientation(decoded);

    final letterbox =
        ImagePreprocessor.letterbox(source, metadata.inputSize);
    final inputData = ImagePreprocessor.toNchwFloat32(letterbox.canvas);

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      metadata.inputShape,
    );
    final runOptions = OrtRunOptions();

    final stopwatch = Stopwatch()..start();
    List<OrtValue?> outputs;
    try {
      outputs = await session.runAsync(
            runOptions,
            {metadata.inputName: inputTensor},
            metadata.outputNames,
          ) ??
          const [];
    } finally {
      inputTensor.release();
      runOptions.release();
    }
    stopwatch.stop();

    try {
      final outputMap = <String, OrtValue>{};
      for (var i = 0; i < metadata.outputNames.length; i++) {
        final value = outputs[i];
        if (value != null) {
          outputMap[metadata.outputNames[i]] = value;
        }
      }

      final detsRaw = outputMap['dets']!.value as List;
      final labelsRaw = outputMap['labels']!.value as List;
      // Both outputs have a leading batch dimension of size 1.
      final dets = (detsRaw[0] as List)
          .map<List<double>>((row) => (row as List).cast<double>())
          .toList();
      final labels = (labelsRaw[0] as List)
          .map<List<double>>((row) => (row as List).cast<double>())
          .toList();

      final detections = DetectionDecoder.decode(
        dets: dets,
        labels: labels,
        classNames: metadata.classNames,
        confidenceThreshold: metadata.confidenceThreshold,
        inputSize: metadata.inputSize,
        letterbox: letterbox,
      );

      return DetectionResult(
        imageWidth: source.width,
        imageHeight: source.height,
        detections: detections,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    if (_envInitialized) {
      OrtEnv.instance.release();
      _envInitialized = false;
    }
  }
}
