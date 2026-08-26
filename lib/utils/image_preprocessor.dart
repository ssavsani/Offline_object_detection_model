import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/constants/model_constants.dart';

/// Result of letterboxing a source image to a square model input.
///
/// [scale] and [padX]/[padY] are kept so detections can be mapped back from
/// the padded square back to the original image's pixel coordinates.
class LetterboxResult {
  final img.Image canvas;
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;

  const LetterboxResult({
    required this.canvas,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });
}

class ImagePreprocessor {
  ImagePreprocessor._();

  /// Resizes [src] to fit within [targetSize]x[targetSize] while preserving
  /// aspect ratio, then pads the remainder with gray so the model always
  /// receives a full-resolution square input (RF-DETR's expected format).
  static LetterboxResult letterbox(img.Image src, int targetSize) {
    final srcW = src.width;
    final srcH = src.height;
    final scale =
        srcW / targetSize > srcH / targetSize
            ? targetSize / srcW
            : targetSize / srcH;
    final newW = (srcW * scale).round();
    final newH = (srcH * scale).round();

    final resized = img.copyResize(
      src,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );

    final pad = ModelConstants.letterboxPadValue;
    final canvas = img.Image(
      width: targetSize,
      height: targetSize,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(pad, pad, pad));

    final padX = (targetSize - newW) ~/ 2;
    final padY = (targetSize - newH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    return LetterboxResult(
      canvas: canvas,
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: srcW,
      originalHeight: srcH,
    );
  }

  /// Converts an RGB [img.Image] into a normalized NCHW float32 tensor:
  /// pixel/255 -> (x - mean) / std -> channel-first layout.
  static Float32List toNchwFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;
    final mean = ModelConstants.normMean;
    final std = ModelConstants.normStd;
    final data = Float32List(3 * h * w);
    final channelSize = h * w;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        final idx = y * w + x;
        data[idx] = ((pixel.r / 255.0) - mean[0]) / std[0];
        data[channelSize + idx] = ((pixel.g / 255.0) - mean[1]) / std[1];
        data[2 * channelSize + idx] = ((pixel.b / 255.0) - mean[2]) / std[2];
      }
    }
    return data;
  }
}
