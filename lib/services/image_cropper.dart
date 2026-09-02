import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/constants/crop_config.dart';
import '../models/bounding_box.dart';

/// Crops the *original* (not the letterboxed/model-input) image around a
/// detection's bounding box, with configurable contextual padding, per the
/// "Crop the Image" spec. Re-decodes the source file the same way
/// [OnnxDetectionService] does (decode + bake EXIF orientation) rather than
/// touching the detector's own decode path, so RF-DETR's behavior is left
/// completely alone.
class ImageCropper {
  ImageCropper._();

  /// Returns JPEG-encoded bytes of the padded, clamped crop.
  ///
  /// Throws a [FormatException] — never lets a bad box reach `image`'s
  /// native crop call — when [bbox] doesn't overlap the image at all, or
  /// the resulting crop (after clamping and padding) is smaller than
  /// [CropConfig.minCropSize] in either dimension. Callers must treat this
  /// as a controlled, expected failure mode, not a crash.
  static Uint8List crop(
    File original,
    BoundingBox bbox, {
    CropConfig config = CropConfig.standard,
  }) {
    final bytes = original.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unable to decode the source image for cropping.');
    }
    final source = img.bakeOrientation(decoded);
    final width = source.width;
    final height = source.height;

    final clampedLeft = bbox.left.clamp(0, width).toDouble();
    final clampedTop = bbox.top.clamp(0, height).toDouble();
    final clampedRight = bbox.right.clamp(0, width).toDouble();
    final clampedBottom = bbox.bottom.clamp(0, height).toDouble();

    if (clampedRight <= clampedLeft || clampedBottom <= clampedTop) {
      throw FormatException(
        'Bounding box [${bbox.left}, ${bbox.top}, ${bbox.right}, '
        '${bbox.bottom}] does not overlap the ${width}x$height source image.',
      );
    }

    final boxWidth = clampedRight - clampedLeft;
    final boxHeight = clampedBottom - clampedTop;
    final padX = boxWidth * config.paddingFraction;
    final padY = boxHeight * config.paddingFraction;

    final paddedLeft = (clampedLeft - padX).clamp(0, width).toDouble();
    final paddedTop = (clampedTop - padY).clamp(0, height).toDouble();
    final paddedRight = (clampedRight + padX).clamp(0, width).toDouble();
    final paddedBottom = (clampedBottom + padY).clamp(0, height).toDouble();

    final cropWidth = (paddedRight - paddedLeft).round();
    final cropHeight = (paddedBottom - paddedTop).round();
    if (cropWidth < config.minCropSize || cropHeight < config.minCropSize) {
      throw FormatException(
        'Crop region ${cropWidth}x$cropHeight is smaller than the minimum '
        '${config.minCropSize}x${config.minCropSize} required.',
      );
    }

    final cropped = img.copyCrop(
      source,
      x: paddedLeft.round(),
      y: paddedTop.round(),
      width: cropWidth,
      height: cropHeight,
    );

    return Uint8List.fromList(img.encodeJpg(cropped, quality: config.jpegQuality));
  }
}
