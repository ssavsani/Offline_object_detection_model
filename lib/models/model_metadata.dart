/// Parsed contents of `assets/models/model_info.json`.
///
/// The Flutter app treats this file as the source of truth for anything
/// that varies per exported model (input size, class labels, confidence
/// threshold) instead of hard-coding them, so re-exporting the model with a
/// different resolution or class list only requires replacing the asset.
class ModelMetadata {
  final String onnxAssetPath;
  final String inputName;
  final List<int> inputShape;
  final int inputSize;
  final List<String> outputNames;
  final List<String> classNames;
  final double confidenceThreshold;

  const ModelMetadata({
    required this.onnxAssetPath,
    required this.inputName,
    required this.inputShape,
    required this.inputSize,
    required this.outputNames,
    required this.classNames,
    required this.confidenceThreshold,
  });

  factory ModelMetadata.fromJson(Map<String, dynamic> json) {
    final inputInfo = (json['input_shapes'] as List).first as Map;
    final shape = (inputInfo['shape'] as List)
        .map((e) => int.parse(e.toString()))
        .toList();
    // shape is NCHW: [batch, channels, height, width]; model is square.
    final inputSize = shape[2];

    final outputs = (json['output_nodes'] as List)
        .map((e) => (e as Map)['name'] as String)
        .toList();

    final decoding =
        (json['flutter_integration'] as Map)['decoding'] as Map;

    return ModelMetadata(
      onnxAssetPath: 'assets/models/${json['onnx_file']}',
      inputName: inputInfo['name'] as String,
      inputShape: shape,
      inputSize: inputSize,
      outputNames: outputs,
      classNames: (json['class_names'] as List).cast<String>(),
      confidenceThreshold:
          (decoding['confidence_threshold'] as num).toDouble(),
    );
  }
}
