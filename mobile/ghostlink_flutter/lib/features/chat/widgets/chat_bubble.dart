import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showReadReceipt;
  final VoidCallback? onLongPress;

  const ChatBubble({
    super.key,
    required this.message,
    required this.showReadReceipt,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 290),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF113F2C) : const Color(0xFF232323),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.text),
              const SizedBox(height: 6),
              Text(
                _metaLabel(),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLabel() {
    final time = _timeLabel(message.createdAt.toLocal());

    if (!showReadReceipt || !message.isMe) {
      return time;
    }

    return '$time • ${message.status}';
  }

  String _timeLabel(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
