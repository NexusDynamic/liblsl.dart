import 'package:flutter/material.dart';
import '../services/background_processor.dart';

class ProgressIndicatorWidget extends StatelessWidget {
  final ProcessingProgress progress;
  final VoidCallback? onCancel;

  const ProgressIndicatorWidget({
    super.key,
    required this.progress,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIconForStage(progress.stage),
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            progress.stage,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (progress.details != null)
            Text(
              progress.details!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: progress.progress,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(progress.progress * 100).toStringAsFixed(1)}%',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ],
      ),
    );
  }

  IconData _getIconForStage(String stage) {
    switch (stage.toLowerCase()) {
      case 'reading files':
        return Icons.file_download;
      case 'processing data':
        return Icons.data_object;
      case 'processing metadata':
        return Icons.code;
      case 'adjusting timestamps':
        return Icons.schedule;
      case 'finalizing':
        return Icons.check_circle_outline;
      case 'complete':
        return Icons.check_circle;
      default:
        return Icons.hourglass_empty;
    }
  }
}

/// Full-screen loading overlay with progress indicator
class LoadingOverlay extends StatelessWidget {
  final ProcessingProgress progress;
  final VoidCallback? onCancel;

  const LoadingOverlay({super.key, required this.progress, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 400),
          child: ProgressIndicatorWidget(
            progress: progress,
            onCancel: onCancel,
          ),
        ),
      ),
    );
  }
}
