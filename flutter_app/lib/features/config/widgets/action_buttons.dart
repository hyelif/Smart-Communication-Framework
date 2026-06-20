import 'package:flutter/material.dart';

import '../../../utils/config_validator.dart';
import '../../../widgets/custom_ui.dart';

/// Deploy, load, import, export, and add-node action buttons.
class ActionButtons extends StatelessWidget {
  final bool isDeploying;
  final bool isLoadingNode;
  final bool isImportingFile;
  final bool isExportingFile;
  final bool isWritingNfc;
  final Esp32Variant selectedVariant;
  final VoidCallback onDeploy;
  final VoidCallback onLoadFromNode;
  final VoidCallback onWriteNfc;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onAddNode;

  const ActionButtons({
    super.key,
    required this.isDeploying,
    required this.isLoadingNode,
    required this.isImportingFile,
    required this.isExportingFile,
    required this.isWritingNfc,
    required this.selectedVariant,
    required this.onDeploy,
    required this.onLoadFromNode,
    required this.onWriteNfc,
    required this.onImport,
    required this.onExport,
    required this.onAddNode,
  });

  @override
  Widget build(BuildContext context) {
    final is30Pin = selectedVariant == Esp32Variant.esp32Node30Pin;

    return Column(
      children: [
        if (is30Pin) ...[
          SizedBox(
            width: double.infinity,
            child: StitchGhostButton(
              onPressed: isLoadingNode ? null : onLoadFromNode,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoadingNode)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.cloud_download_outlined, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isLoadingNode ? 'LOADING...' : 'LOAD FROM NODE',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: StitchGhostButton(
              onPressed: isWritingNfc ? null : onWriteNfc,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isWritingNfc)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.style_rounded, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isWritingNfc ? 'WRITING TAG...' : 'WRITE NFC TAG',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: StitchGhostButton(
                onPressed: isImportingFile ? null : onImport,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isImportingFile)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.file_open_rounded, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isImportingFile ? 'IMPORTING...' : 'IMPORT FILE',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StitchGhostButton(
                onPressed: isExportingFile ? null : onExport,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isExportingFile)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.ios_share_rounded, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isExportingFile ? 'EXPORTING...' : 'EXPORT FILE',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: StitchGhostButton(
            onPressed: onAddNode,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded, size: 18),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'ADD SENSOR NODE',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
