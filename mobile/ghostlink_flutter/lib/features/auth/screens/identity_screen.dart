import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../features/chat/screens/home_screen.dart';
import '../../../features/contacts/screens/qr_scanner_screen.dart';
import '../../../models/chat_contact.dart';

class IdentityScreen extends StatelessWidget {
  final GhostLinkController controller;

  const IdentityScreen({
    super.key,
    required this.controller,
  });

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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        QrImageView(
                          data: identity.verificationUri,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Fingerprint',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          identity.fingerprint,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                color: AppColors.muted,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Verified contacts: $verifiedCount',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: identity.verificationUri));
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verification QR payload copied.')),
                          );
                        },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share QR'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final payload = await Navigator.of(context).push<String>(
                            MaterialPageRoute<String>(
                              builder: (_) => const QrScannerScreen(),
                            ),
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
                              const SnackBar(content: Text('Contact verified.')),
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
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: identity.fingerprint));
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
