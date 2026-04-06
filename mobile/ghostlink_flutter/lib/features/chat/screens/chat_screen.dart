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
      appBar: AppBar(
        titleSpacing: 0,
        title: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final contact = _resolveContact();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact?.displayName ?? contactId),
                const SizedBox(height: 4),
                StatusBadge(
                  status: contact?.status ?? ContactTrustStatus.unverified,
                  compact: true,
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
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final messages = controller.messagesFor(contactId);

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nStart the secure conversation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return ChatBubble(
                      message: message,
                      showReadReceipt: controller.showReadReceipts,
                      onLongPress: () => _showMessageActions(context, message),
                    );
                  },
                );
              },
            ),
          ),
          MessageInput(
            onSend: (text) async {
              try {
                await controller.sendMessage(contactId: contactId, text: text);
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
        ],
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

  void _showMessageActions(BuildContext context, ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.auto_delete),
                title: const Text('Set Self-Destruct (30s)'),
                onTap: () {
                  controller.setSelfDestructTimer(const Duration(seconds: 30));
                  Navigator.of(sheetContext).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete Message (Local)'),
                onTap: () {
                  controller.deleteMessage(contactId, message.id);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
