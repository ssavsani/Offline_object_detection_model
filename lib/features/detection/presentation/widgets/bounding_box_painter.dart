import 'package:flutter/material.dart';

import '../../../../models/detection.dart';

/// Draws detection boxes + labels over an image displayed at [displaySize],
/// scaling from the original image's pixel coordinates ([imageWidth] x
/// [imageHeight]) to whatever size the image widget is actually rendered at.
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;

  BoundingBoxPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });

  static const _palette = [
    Colors.redAccent,
    Colors.lightGreenAccent,
    Colors.amberAccent,
    Colors.cyanAccent,
    Colors.pinkAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.tealAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == 0 || imageHeight == 0) return;
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    for (final detection in detections) {
      final color = _palette[detection.classIndex % _palette.length];
      final box = detection.boundingBox;
      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );

      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, boxPaint);

      final label =
          '${detection.className} ${(detection.confidence * 100).toStringAsFixed(1)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop =
          rect.top - textPainter.height < 0 ? rect.top : rect.top - textPainter.height;
      final labelRect = Rect.fromLTWH(
        rect.left,
        labelTop,
        textPainter.width + 6,
        textPainter.height,
      );
      canvas.drawRect(labelRect, Paint()..color = color.withValues(alpha: 0.9));
      textPainter.paint(canvas, Offset(labelRect.left + 3, labelRect.top));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
