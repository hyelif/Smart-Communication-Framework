import 'package:flutter/material.dart';

class SensorCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  const SensorCard({
    super.key,
    required this.item,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['sensor'] as String,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('GPIO ${item['pin']} - ${item['type']}'),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete, color: theme.colorScheme.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
