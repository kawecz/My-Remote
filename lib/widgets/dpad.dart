import 'package:flutter/material.dart';

class DpadWidget extends StatelessWidget {
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onOk;

  const DpadWidget({
    super.key,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dpadButton(Icons.keyboard_arrow_up, onUp),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dpadButton(Icons.keyboard_arrow_left, onLeft),
              const SizedBox(width: 16),
              _okButton(onOk),
              const SizedBox(width: 16),
              _dpadButton(Icons.keyboard_arrow_right, onRight),
            ],
          ),
          const SizedBox(height: 8),
          _dpadButton(Icons.keyboard_arrow_down, onDown),
        ],
      ),
    );
  }

  Widget _dpadButton(IconData icon, VoidCallback onPressed) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.grey[400]),
        onPressed: onPressed,
        iconSize: 28,
      ),
    );
  }

  Widget _okButton(VoidCallback onPressed) {
    return Container(
      width: 70,
      height: 70,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Center(
        child: TextButton(
          onPressed: onPressed,
          child: const Text(
            'OK',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
