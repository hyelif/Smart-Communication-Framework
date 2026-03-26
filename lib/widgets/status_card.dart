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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "SYSTEM STATUS",
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
              Text(
                "$count Active Devices",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
            label: const Text("Deploy"),
          ),
        ],
      ),
    );
  }
}
