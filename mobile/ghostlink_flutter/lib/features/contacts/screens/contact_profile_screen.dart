import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../models/chat_contact.dart';
import '../../../widgets/common/status_badge.dart';
import 'qr_scanner_screen.dart';

class ContactProfileScreen extends StatelessWidget {
  final GhostLinkController controller;
  final String contactId;

  const ContactProfileScreen({
    super.key,
    required this.controller,
    required this.contactId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Profile')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final contact = _findContact();

          if (contact == null) {
            return const Center(child: Text('Contact not found.'));
          }

          final qrPayload = _verificationUri(contact);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.panelAlt,
                  child: Text(
                    _avatarInitial(contact.displayName),
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  contact.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(child: StatusBadge(status: contact.status)),
                if (contact.riskReason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    contact.riskReason!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        QrImageView(
                          data: qrPayload,
                          size: 190,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Fingerprint',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          contact.fingerprint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'monospace', color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () async {
                    final payload = await Navigator.of(context).push<String>(
                      MaterialPageRoute<String>(builder: (_) => const QrScannerScreen()),
                    );

                    if (payload == null || payload.isEmpty || !context.mounted) {
                      return;
                    }

                    try {
                      await controller.verifyContactPayload(payload);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contact re-verified.')),
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.verified),
                  label: const Text('Verify Again'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () {
                    controller.clearChat(contact.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Local chat deleted.')),
                    );
                  },
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  label: const Text('Delete Chat', style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  ChatContact? _findContact() {
    for (final contact in controller.contacts) {
      if (contact.id == contactId) {
        return contact;
      }
    }
    return null;
  }

  String _verificationUri(ChatContact contact) {
    final payload = {
      'version': 1,
      'id': contact.id,
      'identityKey': contact.identityKey,
      'identitySigningKey': contact.signingKey,
      'fingerprint': contact.fingerprint,
    };

    final token = base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
    return 'ghostlink://verify/$token';
  }

  String _avatarInitial(String name) {
    if (name.isEmpty) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }
}
