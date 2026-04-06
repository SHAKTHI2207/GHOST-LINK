import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../features/contacts/screens/qr_scanner_screen.dart';
import '../../../features/settings/screens/settings_screen.dart';
import '../../../models/chat_contact.dart';
import '../../../widgets/common/status_badge.dart';
import '../../auth/widgets/ghostlink_logo.dart';
import 'chat_screen.dart';

class HomeScreen extends StatelessWidget {
  final GhostLinkController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final chats = controller.contacts;
          final verifiedCount = chats
              .where((chat) => chat.status == ContactTrustStatus.verified)
              .length;

          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bg, AppColors.bgTop],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const GhostLinkLogo(size: 54),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'GhostLink',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      controller.relayConnected
                                          ? 'Relay connected. Secure chats feel instant.'
                                          : 'Connect your relay to start sending securely.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings_outlined),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => SettingsScreen(
                                        controller: controller,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _SummaryCard(
                            relayConnected: controller.relayConnected,
                            relayUrl: controller.relayUrl,
                            verifiedCount: verifiedCount,
                            totalChats: chats.length,
                            onRelayTap: () async {
                              if (controller.relayConnected) {
                                await controller.disconnectRelay();
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Relay disconnected.'),
                                  ),
                                );
                                return;
                              }

                              final relayUrl = await _showRelayInputDialog(
                                context,
                                controller.relayUrl,
                              );
                              if (relayUrl == null ||
                                  relayUrl.trim().isEmpty ||
                                  !context.mounted) {
                                return;
                              }

                              try {
                                await controller.connectRelay(
                                  urlOverride: relayUrl,
                                );
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Relay connected.'),
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
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Chats',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final payload = await Navigator.of(context)
                                      .push<String>(
                                        MaterialPageRoute<String>(
                                          builder: (_) =>
                                              const QrScannerScreen(),
                                        ),
                                      );

                                  if (payload == null ||
                                      payload.isEmpty ||
                                      !context.mounted) {
                                    return;
                                  }

                                  try {
                                    await controller.verifyContactPayload(
                                      payload,
                                    );
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
                                label: const Text('Add contact'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (chats.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyHomeState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                      sliver: SliverList.separated(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final contact = chats[index];

                          return _ChatTile(
                            contact: contact,
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
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Contact verified.')));
          } catch (error) {
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        },
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('New Chat'),
      ),
    );
  }

  Future<String?> _showRelayInputDialog(
    BuildContext context,
    String initialValue,
  ) {
    final relayController = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('Connect Relay'),
          content: TextField(
            controller: relayController,
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
              onPressed: () =>
                  Navigator.of(context).pop(relayController.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final bool relayConnected;
  final String relayUrl;
  final int verifiedCount;
  final int totalChats;
  final VoidCallback onRelayTap;

  const _SummaryCard({
    required this.relayConnected,
    required this.relayUrl,
    required this.verifiedCount,
    required this.totalChats,
    required this.onRelayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [AppColors.panel, AppColors.panelAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.surfaceStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  relayConnected
                      ? 'Secure network online'
                      : 'Relay setup needed',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              StatusBadge(
                status: relayConnected
                    ? ContactTrustStatus.verified
                    : ContactTrustStatus.unverified,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            relayConnected
                ? 'GhostLink is ready for Internet messaging over your configured relay.'
                : 'Connect a relay once and the app behaves like a normal modern messenger.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _MetricPill(label: 'Chats', value: '$totalChats'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MetricPill(label: 'Verified', value: '$verifiedCount'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRelayTap,
            icon: Icon(
              relayConnected
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_sync_outlined,
            ),
            label: Text(relayConnected ? 'Disconnect Relay' : 'Connect Relay'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            relayUrl,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.mutedStrong),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatContact contact;
  final VoidCallback onTap;

  const _ChatTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.surfaceStroke),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.panelSoft,
              child: Text(
                _avatarInitial(contact.displayName),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.displayName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        _timeLabel(contact.lastMessageAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedStrong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    contact.lastMessagePreview ?? 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 10),
                  StatusBadge(status: contact.status, compact: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime? dateTime) {
    if (dateTime == null) {
      return '';
    }

    final local = dateTime.toLocal();
    final now = DateTime.now();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
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
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.surfaceStroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GhostLinkLogo(size: 72),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No chats yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Scan a QR code to verify a contact and start messaging with the same simple flow you expect from a premium messenger.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
