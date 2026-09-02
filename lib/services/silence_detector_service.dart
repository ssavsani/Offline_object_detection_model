import 'dart:async';
import 'dart:math' show sqrt;
import 'dart:typed_data';

/// Detects sustained silence in a live 16kHz mono PCM16 stream by watching
/// per-chunk RMS energy — independent of whatever cadence/latency the
/// speech-to-text engine consuming the same stream has, since that doesn't
/// track real speech pauses precisely enough to gate an auto-stop decision.
///
/// [rmsThreshold] is a normalized (0..1) starting point derived from
/// `whisper_ggml`'s own internal silence-gate constants (which operate on
/// the same normalized PCM16 scale) — real microphones/AGC vary by device,
/// so this needs on-device tuning rather than being treated as exact.
///
/// Callers must feed the *same* stream instance given to the transcription
/// service (e.g. via `.asBroadcastStream()`), and must attach this
/// service's [listen] only after the transcription service has already
/// attached its own listener — broadcast streams don't buffer for late
/// subscribers, so attaching this first could make it the stream's first
/// listener and cause the transcriber to miss the opening of the audio.
class SilenceDetectorService {
  SilenceDetectorService({
    this.silenceDuration = const Duration(milliseconds: 2000),
    this.rmsThreshold = 0.02,
    this.onSilenceStart,
    this.onSilenceCleared,
    this.onSilenceTimeout,
  });

  final Duration silenceDuration;
  final double rmsThreshold;

  /// Fires once when audio first drops below [rmsThreshold] and the
  /// countdown toward [onSilenceTimeout] begins.
  final void Function()? onSilenceStart;

  /// Fires when audio rises back to/above [rmsThreshold] before the
  /// countdown completes, cancelling it.
  final void Function()? onSilenceTimeout;
  final void Function()? onSilenceCleared;

  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  bool _fired = false;

  /// Starts watching [pcm16Chunks] for silence. Cancels any prior
  /// subscription first, so calling this again safely restarts detection
  /// for a new recording session.
  void listen(Stream<Uint8List> pcm16Chunks) {
    cancel();
    _fired = false;
    _subscription = pcm16Chunks.listen(_onChunk);
  }

  void _onChunk(Uint8List chunk) {
    if (_fired) return;
    if (_rms(chunk) >= rmsThreshold) {
      _clearTimer(notify: true);
    } else if (_timer == null) {
      _timer = Timer(silenceDuration, _onTimeout);
      onSilenceStart?.call();
    }
  }

  void _onTimeout() {
    _timer = null;
    _fired = true;
    onSilenceTimeout?.call();
  }

  void _clearTimer({bool notify = false}) {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    if (notify) onSilenceCleared?.call();
  }

  double _rms(Uint8List chunk) {
    final sampleCount = chunk.length ~/ 2;
    if (sampleCount == 0) return 0;
    final samples = ByteData.sublistView(chunk);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = samples.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    return sqrt(sumSquares / sampleCount);
  }

  /// Stops watching and cancels any pending countdown.
  Future<void> cancel() async {
    final subscription = _subscription;
    _subscription = null;
    _clearTimer();
    await subscription?.cancel();
  }
}
