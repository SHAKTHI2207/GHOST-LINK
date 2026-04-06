import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../features/contacts/screens/qr_scanner_screen.dart';
import '../../../features/settings/screens/settings_screen.dart';
import '../../../widgets/common/status_badge.dart';
import 'chat_screen.dart';

class HomeScreen extends StatelessWidget {
  final GhostLinkController controller;

  const HomeScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GhostLink'),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  controller.relayConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: controller.relayConnected ? AppColors.primary : AppColors.warning,
                ),
                onPressed: () async {
                  if (controller.relayConnected) {
                    await controller.disconnectRelay();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Relay disconnected.')),
                    );
                    return;
                  }

                  final relayUrl = await _showRelayInputDialog(context, controller.relayUrl);
                  if (relayUrl == null || relayUrl.trim().isEmpty || !context.mounted) {
                    return;
                  }

                  try {
                    await controller.connectRelay(urlOverride: relayUrl);
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Relay connected.')),
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
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(controller: controller),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final chats = controller.contacts;

          if (chats.isEmpty) {
            return const _EmptyHomeState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final contact = chats[index];

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(
                        controller: controller,
                        contactId: contact.id,
                      ),
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.panelAlt,
                        child: Text(_avatarInitial(contact.displayName)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contact.displayName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contact.lastMessagePreview ?? 'No messages yet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _timeLabel(contact.lastMessageAt),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.muted),
                          ),
                          const SizedBox(height: 6),
                          StatusBadge(status: contact.status, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
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
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<String?> _showRelayInputDialog(BuildContext context, String initialValue) {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connect Relay'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'WebSocket URL',
              hintText: 'ws://127.0.0.1:8080',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  String _timeLabel(DateTime? dateTime) {
    if (dateTime == null) {
      return '';
    }

    final local = dateTime.toLocal();
    final now = DateTime.now();

    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return '${local.day}/${local.month}';
  }

  String _avatarInitial(String name) {
    if (name.isEmpty) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No chats yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Scan a QR code to verify a contact and start messaging.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
