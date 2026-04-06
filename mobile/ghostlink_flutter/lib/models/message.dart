class ChatMessage {
  final String id;
  final String contactId;
  final String text;
  final bool isMe;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String status;

  const ChatMessage({
    required this.id,
    required this.contactId,
    required this.text,
    required this.isMe,
    required this.createdAt,
    this.expiresAt,
    this.status = 'sent',
  });
}
