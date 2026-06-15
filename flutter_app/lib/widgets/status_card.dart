import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final int count;
  final bool isUploading;
  final VoidCallback onUpload;

  const StatusCard({
    super.key,
    required this.count,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SYSTEM STATUS',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                '$count Active Devices',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: isUploading ? null : onUpload,
            icon: isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: const Text('Deploy'),
          ),
        ],
      ),
    );
  }
}
