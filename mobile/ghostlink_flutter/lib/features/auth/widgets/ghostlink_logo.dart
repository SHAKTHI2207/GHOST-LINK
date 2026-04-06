import 'package:flutter/material.dart';

class GhostLinkLogo extends StatelessWidget {
  final double size;

  const GhostLinkLogo({
    super.key,
    this.size = 88,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.27),
        gradient: const LinearGradient(
          colors: [Color(0xFF00FF9C), Color(0xFF00C6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.shield_moon,
        color: Colors.black,
        size: size * 0.48,
      ),
    );
  }
}
