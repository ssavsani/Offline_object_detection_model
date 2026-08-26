/// Fixed preprocessing constants for the RF-DETR Nano export, as documented
/// in `model_info.json` -> flutter_integration.preprocessing.
class ModelConstants {
  ModelConstants._();

  static const String metadataAssetPath = 'assets/models/model_info.json';

  /// ImageNet normalization used by the RF-DETR training pipeline.
  static const List<double> normMean = [0.485, 0.456, 0.406];
  static const List<double> normStd = [0.229, 0.224, 0.225];

  /// Gray padding value used for letterboxing, matching training-time
  /// preprocessing so the model never sees an out-of-distribution pad color.
  static const int letterboxPadValue = 128;
}
