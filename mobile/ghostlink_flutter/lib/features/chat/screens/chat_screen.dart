import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../../../features/chat/widgets/chat_bubble.dart';
import '../../../features/chat/widgets/message_input.dart';
import '../../../features/contacts/screens/contact_profile_screen.dart';
import '../../../models/chat_contact.dart';
import '../../../models/message.dart';
import '../../../widgets/common/status_badge.dart';

class ChatScreen extends StatelessWidget {
  final GhostLinkController controller;
  final String contactId;

  const ChatScreen({
    super.key,
    required this.controller,
    required this.contactId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final contact = _resolveContact();
            final displayName = contact?.displayName ?? contactId;
            return Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.panelSoft,
                  child: Text(_avatarInitial(displayName)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName),
                    const SizedBox(height: 4),
                    StatusBadge(
                      status: contact?.status ?? ContactTrustStatus.unverified,
                      compact: true,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ContactProfileScreen(
                    controller: controller,
                    contactId: contactId,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.bgTop, AppColors.bg],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: kToolbarHeight + 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.panel.withOpacity(0.84),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.surfaceStroke),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.stealthMode
                            ? 'Enhanced privacy active. Timing obfuscation is enabled.'
                            : 'End-to-end encrypted. Security stays invisible while you chat.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final messages = controller.messagesFor(contactId);

                  if (messages.isEmpty) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.panel,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.surfaceStroke),
                        ),
                        child: const Text(
                          'No messages yet.\nStart the secure conversation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, height: 1.5),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - index - 1];
                      return ChatBubble(
                        message: message,
                        showReadReceipt: controller.showReadReceipts,
                        onLongPress: () =>
                            _showMessageActions(context, message),
                      );
                    },
                  );
                },
              ),
            ),
            MessageInput(
              onSend: (text) async {
                try {
                  await controller.sendMessage(
                    contactId: contactId,
                    text: text,
                  );
                } catch (error) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  ChatContact? _resolveContact() {
    for (final contact in controller.contacts) {
      if (contact.id == contactId) {
        return contact;
      }
    }
    return null;
  }

  String _avatarInitial(String name) {
    if (name.isEmpty) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }

  void _showMessageActions(BuildContext context, ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_delete),
                  title: const Text('Set Self-Destruct (30s)'),
                  subtitle: const Text(
                    'Future messages in this chat will expire after 30 seconds.',
                  ),
                  onTap: () {
                    controller.setSelfDestructTimer(
                      const Duration(seconds: 30),
                    );
                    Navigator.of(sheetContext).pop();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete Message (Local)'),
                  subtitle: const Text(
                    'Removes the message from this device only.',
                  ),
                  onTap: () {
                    controller.deleteMessage(contactId, message.id);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
