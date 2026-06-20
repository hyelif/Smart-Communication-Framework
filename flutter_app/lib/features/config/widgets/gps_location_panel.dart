import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// GPS location input panel with latitude/longitude fields and capture button.
class GpsLocationPanel extends StatelessWidget {
  final String latitude;
  final String longitude;
  final bool isFetchingLocation;
  final ValueChanged<String> onLatitudeChanged;
  final ValueChanged<String> onLongitudeChanged;
  final VoidCallback onCapture;

  const GpsLocationPanel({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.isFetchingLocation,
    required this.onLatitudeChanged,
    required this.onLongitudeChanged,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    return StitchPanel(
      color: StitchColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.pin_drop_outlined,
                color: StitchColors.primaryContainer,
              ),
              SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  'NODE LOCATION (GPS)',
                  style: TextStyle(
                    color: StitchColors.primary,
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  minFontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AutoSizeText(
            'Capture your phone GPS location. Node sends this to HQ when config is deployed.',
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            minFontSize: 11,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: onLatitudeChanged,
                  controller: TextEditingController.fromValue(
                    TextEditingValue(text: latitude),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  onChanged: onLongitudeChanged,
                  controller: TextEditingController.fromValue(
                    TextEditingValue(text: longitude),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: StitchPrimaryButton(
              onPressed: isFetchingLocation ? null : onCapture,
              child: isFetchingLocation
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.my_location, size: 18),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'CAPTURE GPS LOCATION',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
