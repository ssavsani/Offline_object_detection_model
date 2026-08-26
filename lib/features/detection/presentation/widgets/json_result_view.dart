import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JsonResultView extends StatelessWidget {
  final Map<String, dynamic> json;

  const JsonResultView({super.key, required this.json});

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(json);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'JSON Result',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                tooltip: 'Copy JSON',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: pretty));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('JSON copied to clipboard')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            pretty,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
