class GhostIdentity {
  final String id;
  final String publicIdentityKey;
  final String signingPublicKey;
  final String fingerprint;
  final String verificationUri;
  final int availableOneTimePreKeys;

  const GhostIdentity({
    required this.id,
    required this.publicIdentityKey,
    required this.signingPublicKey,
    required this.fingerprint,
    required this.verificationUri,
    required this.availableOneTimePreKeys,
  });
}
