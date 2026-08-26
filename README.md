# RF-DETR Nano — Offline Object Detection (Flutter)

A Flutter app that runs a locally-trained **RF-DETR Nano** ONNX model fully
offline on-device (Android & iOS) to detect structural defects
(bridge-cracks, efflorescence, rebar exposure, rust, scaling, spalling,
etc.) in a photo taken with the camera or picked from the gallery.

No network calls are made anywhere in the detection path — the `.onnx`
model and its `model_info.json` metadata are bundled as Flutter assets and
loaded from disk at startup.

## Project layout

```
lib/
  main.dart                                   # App entry point
  core/constants/model_constants.dart         # ImageNet norm + letterbox pad
  models/
    bounding_box.dart
    detection.dart
    detection_result.dart
    model_metadata.dart                       # Parses model_info.json
  services/
    onnx_detection_service.dart                # ORT session lifecycle + detect()
  utils/
    image_preprocessor.dart                    # Letterbox + NCHW tensor build
    detection_decoder.dart                     # RF-DETR output decoding
  features/detection/presentation/
    screens/detection_screen.dart              # Main UI
    widgets/bounding_box_painter.dart
    widgets/detection_list_view.dart
    widgets/json_result_view.dart

assets/models/
  rfdetr-nano.onnx
  model_info.json

python/
  inspect_model.py                             # Static ONNX graph inspection
  validate_inference.py                        # End-to-end Python reference run
  requirements.txt
```

## How the model was inspected

`python/inspect_model.py` loads the ONNX graph directly (`onnx` +
`onnxruntime`) and prints the real input/output names, shapes, dtypes, and
an op-type histogram. This is how the following were confirmed (not
assumed):

- Single input `input`: float32 NCHW `[1, 3, 384, 384]`.
- Two outputs, matched **by name**, not position:
  - `dets`: float32 `[1, 300, 4]`
  - `labels`: float32 `[1, 300, 8]`
- The graph already contains `Sigmoid` and `Softmax` ops internally
  (transformer attention + box regression), which is why the *exported*
  `dets` tensor is already normalized — see below.

`python/validate_inference.py` runs the actual model (via `onnxruntime`) on
a synthetic test image with two known rectangles, applies the exact
preprocessing/postprocessing the Flutter app also implements, and prints
decoded detections. This was used to empirically settle two things
`model_info.json`'s generic notes left ambiguous for *this specific
export*:

1. **`dets` needs no extra sigmoid.** Raw values already sit in
   `[~0, ~1.02]` and decoding them directly as normalized `(cx, cy, w, h)`
   reproduced the two synthetic rectangles' positions almost exactly
   (e.g. a rectangle drawn at pixels `[100,100,500,400]` decoded to
   `[101,99,500,403]`). Applying a second sigmoid would have collapsed all
   boxes toward the center — so the model's internal `Sigmoid` ops already
   cover the box head.
2. **`labels`'s 8 columns map 1:1 to the 8 `class_names`.** The shape
   equals `num_classes` exactly, so there is no extra "no-object" column to
   drop for this export. Each column is an independent logit; a `sigmoid`
   (not `softmax`) is applied per class, since RF-DETR's classification
   head is multi-label.

Run it yourself:

```bash
cd python
python3 -m venv ../.venv && source ../.venv/bin/activate
pip install -r requirements.txt
python3 inspect_model.py
python3 validate_inference.py                 # synthetic test image
python3 validate_inference.py /path/to/photo.jpg   # or a real photo
```

## Preprocessing (must match Python exactly)

Implemented in `lib/utils/image_preprocessor.dart`:

1. Decode the picked/captured image and bake EXIF orientation.
2. **Letterbox** to `384x384`: scale to fit while preserving aspect ratio,
   pad the remainder with solid gray `(128,128,128)`.
3. Convert to RGB float32, scale to `[0,1]`.
4. Normalize per channel with ImageNet stats:
   `mean = [0.485, 0.456, 0.406]`, `std = [0.229, 0.224, 0.225]`.
5. Layout as **NCHW** (`[1, 3, 384, 384]`).

## Postprocessing (RF-DETR-specific, NMS-free)

Implemented in `lib/utils/detection_decoder.dart`:

1. For each of the 300 queries, apply `sigmoid` to each of the 8 class
   logits independently (multi-label, not softmax) and take the arg-max as
   the predicted class + confidence.
2. Keep queries whose best-class confidence exceeds the configured
   threshold (`0.4`, read from `model_info.json`).
3. Convert `(cx, cy, w, h)` (normalized to the 384×384 letterboxed square)
   to corner coordinates, then undo the letterbox scale/padding to map
   back into the original image's pixel space.
4. **No NMS** — RF-DETR's query-based decoder is trained to be
   duplicate-free, so every kept query is emitted as-is.

## Running the app

```bash
flutter pub get
flutter run            # pick a connected device/simulator
```

- **Camera / Gallery** buttons use `image_picker` (delegates to the native
  camera app / native photo picker — no custom camera preview needed for a
  model test harness).
- Detection runs automatically after an image is picked.
- Results render as bounding boxes over the image, a scrollable list of
  `class / confidence / box`, and a copyable formatted JSON block, e.g.:

```json
{
  "image": { "width": 1024, "height": 683 },
  "inferenceTimeMs": 187,
  "detections": [
    {
      "class": "Spallingw",
      "confidence": 0.9679,
      "boundingBox": { "left": 101.07, "top": 98.72, "right": 499.5, "bottom": 403.31 }
    }
  ]
}
```

- If nothing scores above the threshold, the UI shows **"No detection
  found"** instead of an empty list.
- Model-load and inference failures are shown as inline error banners
  instead of crashing.

## Packages used and why

| Package | Purpose |
|---|---|
| `onnxruntime` | Runs the `.onnx` model on-device via `dart:ffi` bindings to the native ONNX Runtime (Android AAR / iOS `onnxruntime-objc` pod). Chosen over `tflite_flutter` because RF-DETR's transformer attention ops are not fully supported by TFLite. |
| `image_picker` | Native camera capture + gallery/photo-picker selection on both platforms. |
| `image` | Pure-Dart image decode/resize/compositing for the letterbox + tensor-building pipeline. |

No backend, HTTP client, or cloud SDK is included — the app cannot make
network calls as part of detection because nothing in the dependency tree
does networking.

## Platform configuration applied

**Android** (`android/app/src/main/AndroidManifest.xml`):
- `CAMERA` permission + optional `android.hardware.camera` feature.
- `READ_EXTERNAL_STORAGE` (capped at API 32; API 33+ gallery access goes
  through the system photo picker, which needs no runtime permission).
- `minSdkVersion`/NDK come from the Flutter-managed default, which already
  satisfies the `onnxruntime` plugin's own requirement of API 21+.

**iOS** (`ios/Runner/Info.plist`):
- `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSPhotoLibraryAddUsageDescription`.
- Deployment target is already `13.0` in the Xcode project, above the
  `onnxruntime` CocoaPod's minimum of iOS 11.0.

## Known limitations

- The bundled test/reference run in `python/validate_inference.py` uses a
  synthetic image (drawn rectangles) because no sample defect photo was
  provided with the model — it validates the *pipeline mechanics*
  (letterbox math, normalization, box decoding), not real-world detection
  accuracy on actual bridge-defect photos.
- `image_picker`'s `ImageSource.camera` opens the platform's native camera
  UI rather than an embedded live preview; sufficient for testing the
  model end-to-end, but not a custom capture experience.
- CPU-only inference (no GPU/NNAPI/CoreML execution provider configured).
  RF-DETR Nano at 384×384 runs acceptably on modern phones on CPU, but very
  old/low-end devices may see multi-second latency.
- No NMS is implemented because RF-DETR is trained to be NMS-free; if a
  future export ever needs it, `DetectionDecoder` is the place to add it.
- The model asset is ~114MB. Loading it copies the bytes from the Flutter
  asset bundle into a native ORT buffer, so expect a transient memory
  spike (roughly 2–3x the model size) during the one-time model load at
  app startup — acceptable on modern phones, but worth knowing on very
  low-RAM devices.
