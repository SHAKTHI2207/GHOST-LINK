enum ContactTrustStatus { verified, unverified, risk }

class ChatContact {
  final String id;
  final String displayName;
  final String identityKey;
  final String signingKey;
  final String fingerprint;
  final ContactTrustStatus status;
  final String? riskReason;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  const ChatContact({
    required this.id,
    required this.displayName,
    required this.identityKey,
    required this.signingKey,
    required this.fingerprint,
    required this.status,
    this.riskReason,
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  ChatContact copyWith({
    String? displayName,
    String? identityKey,
    String? signingKey,
    String? fingerprint,
    ContactTrustStatus? status,
    String? riskReason,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) {
    return ChatContact(
      id: id,
      displayName: displayName ?? this.displayName,
      identityKey: identityKey ?? this.identityKey,
      signingKey: signingKey ?? this.signingKey,
      fingerprint: fingerprint ?? this.fingerprint,
      status: status ?? this.status,
      riskReason: riskReason,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}
