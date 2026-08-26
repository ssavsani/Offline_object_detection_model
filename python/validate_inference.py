"""End-to-end validation of RF-DETR Nano ONNX inference in Python.

Mirrors exactly the preprocessing/postprocessing the Flutter app must implement:
  - letterbox resize to 384x384, pad with gray(128)
  - RGB, /255, normalize with ImageNet mean/std
  - NCHW float32
  - dets: normalized cxcywh -> xyxy -> scale to original image (undo letterbox)
  - labels: sigmoid per class (multi-label), threshold, argmax over classes

Run: python3 python/validate_inference.py [path/to/image.jpg]
If no image is given, a synthetic test image is generated.
"""
import json
import os
import sys

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
MODEL_PATH = os.path.join(HERE, "..", "rfdetr-nano.onnx")
INFO_PATH = os.path.join(HERE, "..", "model_info.json")

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def make_synthetic_image(path, w=1024, h=683):
    img = Image.new("RGB", (w, h), (60, 60, 65))
    d = ImageDraw.Draw(img)
    d.rectangle([100, 100, 500, 400], fill=(180, 60, 40))
    d.ellipse([600, 150, 900, 450], fill=(40, 140, 180))
    d.rectangle([300, 450, 800, 620], fill=(90, 150, 60))
    img.save(path)
    return path


def letterbox(img: Image.Image, target=384, pad_value=128):
    w, h = img.size
    scale = min(target / w, target / h)
    new_w, new_h = int(round(w * scale)), int(round(h * scale))
    resized = img.resize((new_w, new_h), Image.BILINEAR)
    canvas = Image.new("RGB", (target, target), (pad_value, pad_value, pad_value))
    pad_x = (target - new_w) // 2
    pad_y = (target - new_h) // 2
    canvas.paste(resized, (pad_x, pad_y))
    return canvas, scale, pad_x, pad_y


def preprocess(img: Image.Image, target=384):
    canvas, scale, pad_x, pad_y = letterbox(img, target)
    arr = np.asarray(canvas).astype(np.float32) / 255.0  # HWC RGB
    arr = (arr - MEAN) / STD
    arr = arr.transpose(2, 0, 1)  # CHW
    arr = np.expand_dims(arr, 0).astype(np.float32)  # NCHW
    return arr, scale, pad_x, pad_y


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def main():
    with open(INFO_PATH) as f:
        info = json.load(f)
    class_names = info["class_names"]
    conf_thresh = info["flutter_integration"]["decoding"]["confidence_threshold"]

    if len(sys.argv) > 1:
        img_path = sys.argv[1]
        img = Image.open(img_path).convert("RGB")
    else:
        img_path = os.path.join(HERE, "synthetic_test.jpg")
        make_synthetic_image(img_path)
        img = Image.open(img_path).convert("RGB")

    orig_w, orig_h = img.size
    print(f"Input image: {img_path} ({orig_w}x{orig_h})")

    inp, scale, pad_x, pad_y = preprocess(img, target=384)
    print(f"Preprocessed tensor shape: {inp.shape}, dtype={inp.dtype}")
    print(f"letterbox scale={scale:.5f} pad=({pad_x},{pad_y})")

    sess = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
    input_name = sess.get_inputs()[0].name
    outputs = sess.run(None, {input_name: inp})
    out_names = [o.name for o in sess.get_outputs()]
    out_map = dict(zip(out_names, outputs))

    dets = out_map["dets"][0]     # (300, 4)
    labels = out_map["labels"][0]  # (300, 8)

    print(f"\ndets shape={dets.shape} min={dets.min():.4f} max={dets.max():.4f}")
    print(f"labels shape={labels.shape} min={labels.min():.4f} max={labels.max():.4f}")

    probs_sigmoid = sigmoid(labels)
    print(f"\nsigmoid(labels) min={probs_sigmoid.min():.4f} max={probs_sigmoid.max():.4f} "
          f"mean={probs_sigmoid.mean():.4f}")
    print(f"Fraction of sigmoid(labels) > {conf_thresh}: "
          f"{(probs_sigmoid > conf_thresh).mean():.6f}")

    # Also check raw dets range to confirm normalized cxcywh in [0,1]
    print(f"\ndets sample rows (raw, first 5):\n{dets[:5]}")

    best_class_idx = probs_sigmoid.argmax(axis=1)
    best_class_score = probs_sigmoid.max(axis=1)

    order = np.argsort(-best_class_score)
    print("\nTop 10 queries by max class-sigmoid score:")
    for i in order[:10]:
        cls_idx = best_class_idx[i]
        print(f"  query={i:3d} class_idx={cls_idx} class={class_names[cls_idx] if cls_idx < len(class_names) else 'N/A'} "
              f"score={best_class_score[i]:.4f} det(cxcywh_norm)={dets[i]}")

    keep = np.where(best_class_score > conf_thresh)[0]
    print(f"\nDetections above threshold {conf_thresh}: {len(keep)}")

    results = []
    for i in keep:
        cx, cy, w, h = dets[i]
        # cxcywh normalized [0,1] relative to the 384x384 letterboxed square -> to pixel coords in that square
        cx_px, cy_px, w_px, h_px = cx * 384, cy * 384, w * 384, h * 384
        x1 = cx_px - w_px / 2
        y1 = cy_px - h_px / 2
        x2 = cx_px + w_px / 2
        y2 = cy_px + h_px / 2
        # undo letterbox padding + scale -> original image coords
        x1 = (x1 - pad_x) / scale
        y1 = (y1 - pad_y) / scale
        x2 = (x2 - pad_x) / scale
        y2 = (y2 - pad_y) / scale
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(orig_w, x2), min(orig_h, y2)
        cls_idx = int(best_class_idx[i])
        results.append({
            "class": class_names[cls_idx] if cls_idx < len(class_names) else f"cls_{cls_idx}",
            "confidence": float(best_class_score[i]),
            "boundingBox": {
                "left": float(x1), "top": float(y1),
                "right": float(x2), "bottom": float(y2),
            },
        })

    print("\nFinal decoded detections (image coords):")
    print(json.dumps(results, indent=2))

    out_json = os.path.join(HERE, "validation_output.json")
    with open(out_json, "w") as f:
        json.dump({"image": {"width": orig_w, "height": orig_h}, "detections": results}, f, indent=2)
    print(f"\nSaved: {out_json}")


if __name__ == "__main__":
    main()
