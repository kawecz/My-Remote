import 'package:flutter/material.dart';

class VolumeChannelRockerWidget extends StatelessWidget {
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onChannelUp;
  final VoidCallback onChannelDown;
  final VoidCallback onMute;

  const VolumeChannelRockerWidget({
    super.key,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onChannelUp,
    required this.onChannelDown,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildRocker(
            context,
            label: 'Volume',
            topIcon: Icons.keyboard_arrow_up,
            bottomIcon: Icons.keyboard_arrow_down,
            onTop: onVolumeUp,
            onBottom: onVolumeDown,
            showMute: true,
            onMute: onMute,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildRocker(
            context,
            label: 'Canal',
            topLabel: 'CH+',
            bottomLabel: 'CH-',
            onTop: onChannelUp,
            onBottom: onChannelDown,
          ),
        ),
      ],
    );
  }

  Widget _buildRocker(
    BuildContext context, {
    required String label,
    IconData? topIcon,
    IconData? bottomIcon,
    String? topLabel,
    String? bottomLabel,
    required VoidCallback onTop,
    required VoidCallback onBottom,
    bool showMute = false,
    VoidCallback? onMute,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showMute && onMute != null)
              GestureDetector(
                onTap: onMute,
                child: Icon(
                  Icons.volume_off,
                  size: 16,
                  color: Colors.grey[500],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[800]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: onTop,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: topIcon != null
                      ? Icon(topIcon, color: Colors.grey[400])
                      : Text(
                          topLabel!,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              Divider(height: 1, color: Colors.grey[800]),
              InkWell(
                onTap: onBottom,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  child: bottomIcon != null
                      ? Icon(bottomIcon, color: Colors.grey[400])
                      : Text(
                          bottomLabel!,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
