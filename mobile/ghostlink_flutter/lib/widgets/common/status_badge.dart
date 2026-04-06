import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/chat_contact.dart';

class StatusBadge extends StatelessWidget {
  final ContactTrustStatus status;
  final bool compact;

  const StatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: meta.color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: compact ? 14 : 16, color: meta.color),
          const SizedBox(width: 6),
          Text(
            meta.label,
            style: TextStyle(
              color: meta.color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _StatusMeta _statusMeta(ContactTrustStatus status) {
    switch (status) {
      case ContactTrustStatus.verified:
        return const _StatusMeta(
          label: 'Verified',
          icon: Icons.verified_user,
          color: AppColors.primary,
        );
      case ContactTrustStatus.risk:
        return const _StatusMeta(
          label: 'Risk',
          icon: Icons.warning_amber_rounded,
          color: AppColors.danger,
        );
      case ContactTrustStatus.unverified:
        return const _StatusMeta(
          label: 'Unverified',
          icon: Icons.shield_outlined,
          color: AppColors.warning,
        );
    }
  }
}

class _StatusMeta {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusMeta({
    required this.label,
    required this.icon,
    required this.color,
  });
}
