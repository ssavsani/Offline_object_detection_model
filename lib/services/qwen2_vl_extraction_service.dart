import 'dart:typed_data';

import 'package:lib_llama_cpp/lib_llama_cpp.dart';
// lib_llama_cpp's only documented "keep the model loaded across many
// requests" path (LlamaHttpServer, see its README's "Recommended Local
// Server" section) explicitly rejects image/audio content
// ("Image and audio content are not supported in server mode yet." —
// lib_llama_cpp_server's http_server.dart _validateChatRequest). Its other
// public facade, LlamaOpenAIClient.responses/chat.completions, does
// support images via mmprojPath, but reloads the model from a fresh
// isolate on every single call (LlamaResponsesResource._commandsForRequest
// always yields LlamaLoadModelCommand then LlamaDisposeCommand around each
// request) — unusable for section 14's "keep warm" requirement with a
// 1.7GB model pair. InferenceIsolate (this package's own internal
// building block, not re-exported from the top-level barrel) is what
// LlamaOpenAIClient itself is built on: dispatch() returns one
// self-closing Stream<LlamaResponse> per command, so a model can be
// loaded once and reused across many generate calls on the same isolate.
// This mirrors the precedent already set by the app's (removed) Qwen3
// integration, which had to bypass llm_llamacpp's own "recommended" API
// for the same class of reason (see git history / docs).
// ignore: implementation_imports
import 'package:lib_llama_cpp/src/inference_isolate.dart';
import 'package:lib_llama_cpp_platform_interface/lib_llama_cpp_platform_interface.dart';

import '../models/allowed_values.dart';
import 'vlm_extractor.dart';

/// Local Qwen2-VL-2B-Instruct (GGUF + mmproj, via llama.cpp's `mtmd` vision
/// path, `qwen2vl_merger` projector) image+text extraction. Only ever given
/// the cropped detection region and the user's text — this is the one
/// component in the pipeline that actually processes image pixels. Returns
/// the model's raw text response; this service does not parse or trust it
/// — [ValidationService] does that.
///
/// Replaces the SmolVLM2-2.2B model this service used to wrap
/// (`SmolVlmExtractionService`, see git history) — same [VlmExtractor]
/// contract, same `lib_llama_cpp` `mtmd` call shape (`LlamaLoadModelCommand`
/// / `LlamaGenerateMessagesCommand`), only the model/mmproj GGUF pair
/// changed. Deliberately kept on the same plain-prose JSON prompt (not
/// grammar-constrained tool-calling): SmolVLM2 was tested against a
/// grammar-constrained variant on-device (2026-08-31, see
/// docs/OFFLINE_AI_IMPLEMENTATION.md) and produced 100%-parseable but
/// completely degenerate field content, so tool-calling was avoided here
/// too. That finding was specific to SmolVLM2, was never trained for
/// tool/function calling — it has **not** been re-verified against Qwen2-VL,
/// which may behave differently; worth a fresh on-device check before
/// assuming either outcome.
///
/// Reloads the model before every [extract] call, on a kept-warm isolate.
/// This is deliberate, not an oversight: `lib_llama_cpp` gives no way to
/// reset a context's KV cache between independent single-shot requests —
/// its raw FFI layer has `llama_memory_clear`, but that native handle is
/// only reachable from inside the package's own isolate worker, which
/// nothing outside the package (including this file's `InferenceIsolate`
/// use) can call into. Confirmed on-device: reusing one loaded context for
/// a second, independent multimodal generation fails with
/// `mtmd_helper_eval_chunks failed with code -1` — the vision-token
/// evaluation path doesn't tolerate a KV cache still holding the previous
/// request's state. `loadModel()` disposes and recreates the context from
/// scratch internally, so reloading is the only correctness-preserving
/// option available through this package today; only the isolate and
/// resolved native library (not the model weights/context) stay warm.
class Qwen2VlExtractionService implements VlmExtractor {
  InferenceIsolate? _actor;

  Future<InferenceIsolate> _ensureIsolate() async {
    final existing = _actor;
    if (existing != null) return existing;

    final platform = LibLlamaCppPlatform.instance;
    final library =
        await platform.resolveLibrary(request: const LlamaCppLibraryRequest());
    final actor = await InferenceIsolate.spawn(
      library: library,
      initialState: const LlamaState.empty(),
    );
    _actor = actor;
    return actor;
  }

  Future<void> _loadModel(
    InferenceIsolate actor,
    String modelPath,
    String mmprojPath,
  ) async {
    final loadResponses = await actor
        .dispatch(LlamaLoadModelCommand(
          modelPath: modelPath,
          mmprojPath: mmprojPath,
          // Performance tuning: this app's prompt + one cropped image +
          // short JSON response comfortably fits in a few hundred tokens,
          // but the package's own default (contextSize null -> n_ctx=0,
          // which llama.cpp resolves to the model's full training
          // context) allocates a KV cache sized for that much larger
          // context on every single reload. imageMin/MaxTokens cap the
          // vision encoder's token budget (mtmd's own
          // image_min_tokens/image_max_tokens options) — a direct,
          // supported lever over effective image-resolution cost
          // regardless of the crop's actual pixel size. Particularly
          // relevant for Qwen2-VL, whose "naive dynamic resolution"
          // vision encoder can otherwise emit a much larger, image-size-
          // dependent token count than SmolVLM2's fixed tiling did.
          // Values carried over unchanged from the SmolVLM2 setup;
          // conservative for a coarse defect-classification task (not
          // fine-grained OCR), but not yet re-validated against Qwen2-VL's
          // own on-device timings — see docs/OFFLINE_AI_IMPLEMENTATION.md
          // before tightening further.
          contextSize: 2048,
          imageMinTokens: 64,
          imageMaxTokens: 256,
        ))
        .toList();
    LlamaErrorResponse? loadError;
    for (final response in loadResponses) {
      if (response is LlamaErrorResponse) {
        loadError = response;
        break;
      }
    }
    if (loadError != null) {
      throw StateError('Failed to load Qwen2-VL model: ${loadError.message}');
    }
  }

  @override
  Future<String> extract({
    required String modelPath,
    required String mmprojPath,
    required Uint8List imageBytes,
    required String label,
    required String userText,
    required AllowedValues allowedValues,
  }) async {
    final actor = await _ensureIsolate();
    await _loadModel(actor, modelPath, mmprojPath);

    final responses = await actor
        .dispatch(LlamaGenerateMessagesCommand(
          messages: [
            LlamaMessage(
              role: 'user',
              content: [
                LlamaTextPart(_prompt(
                  label: label,
                  userText: userText,
                  allowedValues: allowedValues,
                )),
                LlamaImageBytesPart(bytes: imageBytes, mimeType: 'image/jpeg'),
              ],
            ),
          ],
          // Short, low-temperature generation: the expected output is one
          // small JSON object, not free-form prose — matches section 8's
          // "keep the prompt short... do not ask for long explanations".
          maxTokens: 220,
          temperature: 0.1,
        ))
        .toList();

    final buffer = StringBuffer();
    for (final response in responses) {
      switch (response) {
        case LlamaTokenResponse(:final text):
          buffer.write(text);
        case LlamaErrorResponse(:final message):
          throw StateError('Qwen2-VL generation failed: $message');
        case LlamaToolCallResponse() ||
            LlamaStateChangedResponse() ||
            LlamaReadyResponse() ||
            LlamaDoneResponse():
          break;
      }
    }
    return buffer.toString();
  }

  /// Embeds the app's real controlled-value vocabulary directly in the
  /// prompt (locations/work packages/assignees/issue types) so the model
  /// maps natural language onto the correct predefined values (e.g. "civil
  /// work" -> "Civil", "floor2" -> a matching location) instead of
  /// inventing free text that would just get rejected downstream by
  /// ValidationService. Kept short and structured for both accuracy and
  /// inference speed, per the "concise, deterministic prompt" requirement.
  String _prompt({
    required String label,
    required String userText,
    required AllowedValues allowedValues,
  }) {
    final severities = AllowedValues.severities.join('/');
    final issueTypes = allowedValues.issueTypes.join(', ');
    final workpackages = allowedValues.packages.join(', ');
    final locations = allowedValues.locations.join(', ');
    final assignees = allowedValues.assignees.join(', ');

    return '''
Inspection photo. Detected object: $label.
Inspector's note: "${userText.trim().isEmpty ? '(none)' : userText.trim()}"

Look at the image and the note together. Reply with exactly one JSON
object and nothing else — no explanation, no markdown:

{"title":"","description":"","severity":"","issue_type":"","location":"","workpackage":"","assign_to":""}

Field rules — use "" for anything not shown in the image or stated in the
note; never invent a value that isn't in the lists below:
- title: short defect title.
- description: concise issue summary, e.g. "Rebar issue on wall".
- severity: one of $severities, based on how serious the defect looks.
- issue_type: closest match from: $issueTypes.
- location: only if the note names one, closest match from: $locations.
- workpackage: the trade/work needed, only if named or clearly implied by
  the note (e.g. "civil work" -> "Civil"), closest match from: $workpackages.
- assign_to: only if the note names a person, closest match from: $assignees.
''';
  }

  /// Closes the inference isolate. Safe to call when nothing is loaded.
  /// Call this when done with the whole session (e.g. leaving the screen).
  Future<void> release() async {
    _actor?.close();
    _actor = null;
  }

  void dispose() {
    _actor?.close();
  }
}
