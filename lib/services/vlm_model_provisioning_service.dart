import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Explicit, user-triggered acquisition of the local Qwen2-VL-2B-Instruct
/// weights (GGUF + multimodal projector), mirroring the app's existing
/// offline model-provisioning pattern: fetched once into app-local storage
/// via an explicit "Download" action — never automatically, and never as
/// part of the analysis path itself.
///
/// Replaces the SmolVLM2-2.2B-Instruct weights this service used to fetch
/// (see git history / [[project-smolvlm2-pipeline-status]] in memory) —
/// same download/provisioning shape (two GGUF files: base model + mmproj,
/// same `ggml-org` publisher, same Q4_K_M/Q8_0 quantization pairing), only
/// the repo/file identifiers changed. Total download size is coincidentally
/// almost identical to the old SmolVLM2-2.2B pair (~1.7GB either way), so
/// the app's user-facing "~1.7GB, one-time download" copy did not need to
/// change.
class VlmModelProvisioningService {
  static const repoId = 'ggml-org/Qwen2-VL-2B-Instruct-GGUF';
  static const modelFileName = 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf';
  static const mmprojFileName = 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf';

  // Approximate published sizes (986 MB / 710 MB), used only to weight
  // the combined progress stream between the two files reasonably.
  static const double _modelWeight = 0.58;

  Future<String> _targetDir() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/models';
  }

  Future<String> get modelPath async => '${await _targetDir()}/$modelFileName';
  Future<String> get mmprojPath async => '${await _targetDir()}/$mmprojFileName';

  Future<bool> isModelDownloaded() async {
    final model = File(await modelPath);
    final mmproj = File(await mmprojPath);
    return model.existsSync() && mmproj.existsSync();
  }

  /// Downloads both the model and its multimodal projector, yielding
  /// combined progress in [0.0, 1.0]. Throws on failure (e.g. no network)
  /// rather than completing silently, so a failed/partial download is
  /// never mistaken for a ready model — each file is written to a `.part`
  /// path and only renamed into place once fully downloaded.
  Stream<double> download() async* {
    final dir = await _targetDir();
    await Directory(dir).create(recursive: true);

    yield* _downloadFile(
      modelFileName,
      await modelPath,
      progressStart: 0.0,
      progressWeight: _modelWeight,
    );
    yield* _downloadFile(
      mmprojFileName,
      await mmprojPath,
      progressStart: _modelWeight,
      progressWeight: 1.0 - _modelWeight,
    );
  }

  Stream<double> _downloadFile(
    String fileName,
    String destinationPath, {
    required double progressStart,
    required double progressWeight,
  }) async* {
    final uri = Uri.parse('https://huggingface.co/$repoId/resolve/main/$fileName');
    final client = http.Client();
    final partPath = '$destinationPath.part';
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download $fileName: HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = File(partPath).openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            yield progressStart + progressWeight * (received / total);
          }
        }
      } finally {
        await sink.close();
      }

      await File(partPath).rename(destinationPath);
    } finally {
      client.close();
    }
  }

  void dispose() {}
}
