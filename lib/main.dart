import 'package:flutter/material.dart';

import 'features/detection/presentation/screens/detection_screen.dart';

void main() {
  runApp(const RfDetrApp());
}

class RfDetrApp extends StatelessWidget {
  const RfDetrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RF-DETR Object Detection',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const DetectionScreen(),
    );
  }
}
