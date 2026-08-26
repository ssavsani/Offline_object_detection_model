import 'package:flutter/material.dart';

import '../../../../models/detection.dart';

class DetectionListView extends StatelessWidget {
  final List<Detection> detections;

  const DetectionListView({super.key, required this.detections});

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No detection found',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: detections.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final d = detections[index];
        final box = d.boundingBox;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(
            d.className,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'left: ${box.left.toStringAsFixed(0)}, top: ${box.top.toStringAsFixed(0)}, '
            'right: ${box.right.toStringAsFixed(0)}, bottom: ${box.bottom.toStringAsFixed(0)}',
          ),
          trailing: Text(
            '${(d.confidence * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}
