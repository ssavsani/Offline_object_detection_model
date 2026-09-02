import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:whisper_ggml/whisper_ggml.dart';

/// Offline speech-to-text via a bundled Whisper base.en model (ggml,
/// q5_1-quantized), per `03_VOICE_WHISPER.md`.
///
/// Uses `package:whisper_ggml`'s live session so recognized words are
/// visible *while the user is speaking*, not only after they stop —
/// required by the unified capture screen. Never performs a network call:
/// the model ships as a Flutter asset
/// (`assets/models/whisper/ggml-base.en-q5_1.bin`) and is copied once to the
/// filesystem path `WhisperController` resolves for [WhisperModel.baseEn]
/// (`ggml-base.en.bin` — the quantization is read from the file's own GGUF
/// header, not inferred from the filename, so reusing that path is safe).
/// `package:whisper_ggml`'s own `downloadModel()` HTTP path is never called.
class VoiceTranscriptionService {
  static const _model = WhisperModel.baseEn;
  static const _bundledAssetPath =
      'assets/models/whisper/ggml-base.en-q5_1.bin';

  final WhisperController _controller = WhisperController();
  bool _modelFileReady = false;
  WhisperLiveSession? _session;

  Future<void> _ensureModelFile() async {
    if (_modelFileReady) return;
    final path = await _controller.getPath(_model);
    final file = File(path);
    if (!await file.exists()) {
      final data = await rootBundle.load(_bundledAssetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _modelFileReady = true;
  }

  /// Starts a live transcription session fed by [pcm16Stream] (16kHz mono
  /// little-endian PCM16, e.g. from [AudioRecorderService.startStream]).
  /// Returns a stream of progressively-refined *full* transcripts (each
  /// event replaces the previous one) for live on-screen display. Throws on
  /// setup failure (corrupt bundled asset, native init failure) — the
  /// caller must surface that, not swallow it.
  Future<Stream<String>> startLiveSession(Stream<Uint8List> pcm16Stream) async {
    await _ensureModelFile();
    final session = await _controller.transcribeLive(
      model: _model,
      pcm16Stream: pcm16Stream,
      lang: 'en',
    );
    _session = session;
    return session.partials;
  }

  /// Finalizes the current live session and returns the final transcript,
  /// or null if there is no active session or the result is empty — per
  /// `03_VOICE_WHISPER.md`, null must not produce a form change. Throws if
  /// the native session itself fails while finishing.
  Future<String?> stopLiveSession() async {
    final session = _session;
    _session = null;
    if (session == null) return null;
    final text = (await session.stop()).trim();
    return text.isEmpty ? null : text;
  }

  /// Releases the native model from memory, per `09_OFFLINE_RUNTIME.md`'s
  /// load/use/release lifecycle. Safe to call even if nothing is loaded.
  Future<void> release() => _controller.releaseModel();
}
