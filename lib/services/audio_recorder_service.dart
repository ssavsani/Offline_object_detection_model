import 'dart:typed_data';

import 'package:record/record.dart';

/// Thin wrapper around `package:record`'s streaming API — 16kHz mono PCM16,
/// the format [VoiceTranscriptionService]'s live session needs to show
/// recognized words while the user is still speaking, per
/// `03_VOICE_WHISPER.md`. Callers must check [hasPermission] before
/// [startStream].
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<Stream<Uint8List>> startStream() {
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
