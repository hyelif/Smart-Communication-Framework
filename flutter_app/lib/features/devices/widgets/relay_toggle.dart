import 'package:flutter/material.dart';

/// A toggle switch for controlling a relay on a remote node.
///
/// Writes to `relay_commands` table in Turso when toggled.
/// The HQ Gateway picks up the command on its next poll cycle (~4s).
///
/// Currently a presentational widget — the actual Turso write
/// will be wired in when the [DeviceDetailController] is built.
class RelayToggle extends StatefulWidget {
  /// The hardware ID of the target node.
  final String hardwareId;

  /// The relay index (0-based) on the node.
  final int relayId;

  /// Human-readable label for this relay (e.g. "Pump", "Light").
  final String label;

  /// Whether the relay is currently ON.
  final bool isOn;

  /// Called when the user toggles the switch.
  ///
  /// The parent should handle the Turso write and update state.
  final ValueChanged<bool>? onToggle;

  /// Whether a command is currently in-flight.
  final bool busy;

  const RelayToggle({
    super.key,
    required this.hardwareId,
    required this.relayId,
    required this.label,
    required this.isOn,
    this.onToggle,
    this.busy = false,
  });

  @override
  State<RelayToggle> createState() => _RelayToggleState();
}

class _RelayToggleState extends State<RelayToggle> {
  late bool _internalState;

  @override
  void initState() {
    super.initState();
    _internalState = widget.isOn;
  }

  @override
  void didUpdateWidget(RelayToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync internal state if the parent updated isOn externally
    // (e.g. after a successful Turso write or a poll response).
    if (oldWidget.isOn != widget.isOn) {
      _internalState = widget.isOn;
    }
  }

  Future<void> _onToggle(bool value) async {
    if (widget.busy) return;

    setState(() => _internalState = value);
    widget.onToggle?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _internalState
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            size: 20,
            color: _internalState
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.busy
                      ? 'Sending...'
                      : (_internalState ? 'ON' : 'OFF'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _internalState
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (widget.busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Switch.adaptive(
              value: _internalState,
              onChanged: _onToggle,
            ),
        ],
      ),
    );
  }
}
