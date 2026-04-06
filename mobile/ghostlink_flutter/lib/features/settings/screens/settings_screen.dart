import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';

class SettingsScreen extends StatelessWidget {
  final GhostLinkController controller;

  const SettingsScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Mode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: controller.stealthMode,
                        onChanged: controller.setStealthMode,
                        title: Text(controller.stealthMode ? 'Stealth Mode ON' : 'Fast Mode ON'),
                        subtitle: Text(
                          controller.stealthMode
                              ? 'Enhanced Privacy Active: random delays, reduced metadata.'
                              : 'Fast delivery mode with standard privacy defaults.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Self-Destruct Timer',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
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
                          controller.setSelfDestructTimer(Duration(seconds: seconds));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Read Receipts',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: controller.showReadReceipts,
                        onChanged: controller.setReadReceipts,
                        title: const Text('Show Delivered/Seen for outgoing messages'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Card(
                child: ListTile(
                  title: Text('Blocked Devices'),
                  subtitle: Text('No blocked devices in MVP build.'),
                  trailing: Icon(Icons.block_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  title: const Text('Export Keys (Advanced)'),
                  subtitle: const Text('Copies your verification URI to clipboard.'),
                  trailing: const Icon(Icons.key),
                  onTap: () async {
                    final identity = controller.identity;
                    if (identity == null) {
                      return;
                    }

                    await Clipboard.setData(ClipboardData(text: identity.verificationUri));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Verification URI copied.')),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  'Current Relay: ${controller.relayUrl}\nIdentity: ${controller.identity?.id ?? 'not set'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
