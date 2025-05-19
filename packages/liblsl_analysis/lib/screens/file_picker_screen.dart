import 'package:flutter/material.dart';

class FilePickerScreen extends StatelessWidget {
  final VoidCallback onPickFile;
  final bool isLoading;

  const FilePickerScreen({
    super.key,
    required this.onPickFile,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.upload_file, size: 80, color: Colors.deepPurple),
          const SizedBox(height: 20),
          const Text(
            'Select a CSV file to analyze',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 40),
          if (isLoading)
            const CircularProgressIndicator()
          else
            ElevatedButton.icon(
              onPressed: onPickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Open CSV File'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Your data will be processed locally',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
