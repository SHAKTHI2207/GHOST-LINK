import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';

class SettingsScreen extends StatelessWidget {
  final GhostLinkController controller;

  const SettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bg, AppColors.bgTop],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _SettingsCard(
                  title: 'Privacy Mode',
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: controller.stealthMode,
                    onChanged: controller.setStealthMode,
                    title: Text(
                      controller.stealthMode
                          ? 'Stealth Mode ON'
                          : 'Fast Mode ON',
                    ),
                    subtitle: Text(
                      controller.stealthMode
                          ? 'Enhanced Privacy Active: random delays and reduced metadata.'
                          : 'Faster delivery with standard privacy defaults.',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsCard(
                  title: 'Self-Destruct Timer',
                  child: DropdownButtonFormField<int>(
                    value: controller.selfDestructTimer.inSeconds,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Off')),
                      DropdownMenuItem(value: 30, child: Text('30 seconds')),
                      DropdownMenuItem(value: 300, child: Text('5 minutes')),
                      DropdownMenuItem(value: 3600, child: Text('1 hour')),
                    ],
                    onChanged: (seconds) {
                      if (seconds == null) {
                        return;
                      }
                      controller.setSelfDestructTimer(
                        Duration(seconds: seconds),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsCard(
                  title: 'Read Receipts',
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: controller.showReadReceipts,
                    onChanged: controller.setReadReceipts,
                    title: const Text('Show delivered and seen states'),
                    subtitle: const Text(
                      'Controls whether outgoing messages show receipt labels in chat.',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsCard(
                  title: 'Advanced',
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Blocked Devices'),
                        subtitle: const Text(
                          'No blocked devices in the MVP build.',
                        ),
                        trailing: const Icon(Icons.block_outlined),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Export Keys'),
                        subtitle: const Text(
                          'Copies your verification URI to clipboard.',
                        ),
                        trailing: const Icon(Icons.key_rounded),
                        onTap: () async {
                          final identity = controller.identity;
                          if (identity == null) {
                            return;
                          }

                          await Clipboard.setData(
                            ClipboardData(text: identity.verificationUri),
                          );
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Verification URI copied.'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.surfaceStroke),
                  ),
                  child: Text(
                    'Current Relay: ${controller.relayUrl}\nIdentity: ${controller.identity?.id ?? 'not set'}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
