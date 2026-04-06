import 'package:flutter/material.dart';

class GhostLinkLogo extends StatelessWidget {
  final double size;

  const GhostLinkLogo({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF25D366).withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.30),
          gradient: const LinearGradient(
            colors: [Color(0xFF7CF7A9), Color(0xFF25D366), Color(0xFF5DA9FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: size * 0.12,
              left: size * 0.14,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.28),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Icon(
              Icons.shield_moon_rounded,
              color: Colors.black,
              size: size * 0.50,
            ),
          ],
        ),
      ),
    );
  }
}
