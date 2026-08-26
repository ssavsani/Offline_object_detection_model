/// Axis-aligned bounding box in original-image pixel coordinates.
class BoundingBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;

  Map<String, dynamic> toJson() => {
        'left': double.parse(left.toStringAsFixed(2)),
        'top': double.parse(top.toStringAsFixed(2)),
        'right': double.parse(right.toStringAsFixed(2)),
        'bottom': double.parse(bottom.toStringAsFixed(2)),
      };
}
