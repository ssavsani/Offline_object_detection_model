/// Configurable crop parameters for [ImageCropper], kept in one place per
/// the implementation spec's "do not hardcode the padding in multiple
/// places" requirement.
class CropConfig {
  /// Fraction of the bounding box's width/height added as contextual
  /// padding on each side before cropping (e.g. 0.15 = 15%).
  final double paddingFraction;

  /// A crop narrower or shorter than this many pixels (after clamping to
  /// the source image) is rejected as too small to be a meaningful region
  /// for the VLM, rather than sent through anyway.
  final int minCropSize;

  /// JPEG quality (1-100) used when encoding the crop for the VLM.
  final int jpegQuality;

  const CropConfig({
    this.paddingFraction = 0.15,
    this.minCropSize = 16,
    this.jpegQuality = 90,
  });

  static const CropConfig standard = CropConfig();
}
