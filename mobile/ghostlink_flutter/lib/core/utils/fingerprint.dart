String formatFingerprint(String hex, {int group = 2}) {
  final raw = hex.replaceAll(':', '').toUpperCase();
  if (raw.isEmpty) {
    return '';
  }

  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i += group) {
    if (i > 0) {
      buffer.write(':');
    }

    final end = (i + group <= raw.length) ? i + group : raw.length;
    buffer.write(raw.substring(i, end));
  }

  return buffer.toString();
}
