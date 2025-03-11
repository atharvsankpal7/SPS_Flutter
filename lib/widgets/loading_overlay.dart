import 'package:flutter/material.dart';
import 'dart:async';

class LoadingProgressOverlay extends StatelessWidget {
  final StreamController<double> progressController;

  const LoadingProgressOverlay({
    required this.progressController,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<double>(
                stream: progressController.stream,
                builder: (context, snapshot) {
                  return Column(
                    children: [
                      CircularProgressIndicator(
                        value: snapshot.data,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _getProgressMessage(snapshot.data ?? 0),
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getProgressMessage(double progress) {
    if (progress < 0.2) return 'Preparing data...';
    if (progress < 0.6) return 'Generating charts...';
    if (progress < 0.8) return 'Creating PDF...';
    return 'Saving PDF...';
  }
}