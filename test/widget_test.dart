import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rfdetr_object_detection/main.dart';

void main() {
  testWidgets('App renders the detection screen title', (tester) async {
    await tester.pumpWidget(const RfDetrApp());

    expect(find.text('RF-DETR Nano Object Detection'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.byIcon(Icons.photo_library), findsOneWidget);
  });
}
