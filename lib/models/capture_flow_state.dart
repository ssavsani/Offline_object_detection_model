/// The per-capture-session flow state for [DetectionScreen]'s automatic
/// voice-driven pipeline: image -> detect -> auto-record -> live transcript
/// -> silence -> auto-analyze -> result. Deliberately separate from the
/// screen's one-time model-loading concerns (`_ModelStatus`/`_VlmStatus`),
/// which are a different axis and don't reset per image.
enum CaptureFlowState {
  /// Nothing picked yet, or the last detection found nothing — both cases
  /// behave identically (no auto-actions in flight, manual controls
  /// available), so they share one value rather than needing a 10th.
  idle,

  /// RF-DETR Nano is running on the selected image.
  detectingObjects,

  /// Detection succeeded with at least one result; about to auto-start
  /// recording.
  objectDetected,

  /// Mic is open, live transcription is running, no silence detected yet.
  recording,

  /// Audio has dropped below the silence threshold and is accumulating
  /// toward the auto-stop timeout; reverts to [recording] if speech
  /// resumes before the timeout fires.
  silenceCountdown,

  /// Recording/transcription is being torn down and the final transcript
  /// resolved.
  finalizingTranscript,

  /// The RF-DETR-crop -> Qwen2-VL (+ rules engine) analysis is running.
  analyzing,

  /// Analysis finished and the result screen was opened.
  completed,

  /// A recoverable failure occurred (permission denied, recorder/whisper
  /// throw, no speech detected, etc.) — manual retry via the mic/Analyze
  /// buttons remains available.
  error,
}
