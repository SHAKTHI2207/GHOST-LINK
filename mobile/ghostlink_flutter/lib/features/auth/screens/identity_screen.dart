import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../features/chat/screens/home_screen.dart';
import '../../../features/contacts/screens/qr_scanner_screen.dart';
import '../../../features/auth/widgets/ghostlink_logo.dart';
import '../../../models/chat_contact.dart';

class IdentityScreen extends StatelessWidget {
  final GhostLinkController controller;

  const IdentityScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final identity = controller.identity;

    if (identity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Identity')),
        body: const Center(child: Text('Identity not initialized.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your Identity')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final verifiedCount = controller.contacts
              .where((contact) => contact.status == ContactTrustStatus.verified)
              .length;

          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bg, AppColors.bgTop],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppColors.surfaceStroke),
                    ),
                    child: Column(
                      children: [
                        const GhostLinkLogo(size: 68),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          identity.id,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Ready to share securely',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: QrImageView(
                            data: identity.verificationUri,
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _MetricRow(
                          label: 'Verified contacts',
                          value: '$verifiedCount',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _MetricRow(
                          label: 'Fingerprint',
                          value: _shortFingerprint(identity.fingerprint),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.panelAlt,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.surfaceStroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fingerprint',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          identity.fingerprint,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontFamily: 'monospace',
                                color: AppColors.muted,
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: identity.verificationUri),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Verification QR payload copied.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Share QR'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final payload = await Navigator.of(context)
                                .push<String>(
                                  MaterialPageRoute<String>(
                                    builder: (_) => const QrScannerScreen(),
                                  ),
                                );

                            if (payload == null ||
                                payload.isEmpty ||
                                !context.mounted) {
                              return;
                            }

                            try {
                              await controller.verifyContactPayload(payload);
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Contact verified.'),
                                ),
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
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Scan QR'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: identity.fingerprint),
                      );
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fingerprint copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy Fingerprint'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeScreen(controller: controller),
                        ),
                      );
                    },
                    child: const Text('Continue to Chats'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _shortFingerprint(String value) {
    if (value.length < 20) {
      return value;
    }

    return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
