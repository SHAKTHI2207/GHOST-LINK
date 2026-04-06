import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  final StreamController<Map<String, dynamic>> _deliveriesController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final Random _random = Random.secure();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _authCompleter;
  bool _connected = false;

  bool get isConnected => _connected;
  Stream<Map<String, dynamic>> get deliveries => _deliveriesController.stream;

  Future<void> connect({required String url, required String userId}) async {
    await disconnect();

    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    _authCompleter = Completer<void>();

    _subscription = channel.stream.listen(
      _onRawMessage,
      onError: (Object error, StackTrace stackTrace) {
        _failPending(error);
        _connected = false;
      },
      onDone: () {
        _failPending(StateError('Relay socket closed.'));
        _connected = false;
      },
    );

    _sendRaw({
      'type': 'auth',
      'userId': userId,
    });

    await _authCompleter!.future.timeout(const Duration(seconds: 10));
    _connected = true;
  }

  Future<Map<String, dynamic>> publishPrekeys(Map<String, dynamic> bundle) {
    return request('publish_prekeys', {'bundle': bundle});
  }

  Future<Map<String, dynamic>> fetchPrekeyBundle(String targetId) async {
    final response = await request('fetch_prekey_bundle', {'targetId': targetId});
    return response['bundle'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendPacket({
    required String to,
    required Map<String, dynamic> packet,
  }) {
    return request('send_packet', {
      'to': to,
      'packet': packet,
    });
  }

  Future<Map<String, dynamic>> request(
    String type,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_channel == null) {
      throw const StateError('Socket not connected.');
    }

    final requestId = _requestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;

    _sendRaw({
      'type': type,
      'requestId': requestId,
      ...payload,
    });

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(requestId);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _connected = false;
    _authCompleter = null;

    final oldSubscription = _subscription;
    _subscription = null;
    await oldSubscription?.cancel();

    final oldChannel = _channel;
    _channel = null;
    await oldChannel?.sink.close();

    _failPending(StateError('Socket disconnected.'));
  }

  void dispose() {
    unawaited(disconnect());
    _deliveriesController.close();
  }

  void _onRawMessage(dynamic rawData) {
    Map<String, dynamic> message;

    try {
      if (rawData is String) {
        message = jsonDecode(rawData) as Map<String, dynamic>;
      } else {
        message = jsonDecode(utf8.decode(rawData as List<int>)) as Map<String, dynamic>;
      }
    } catch (_) {
      return;
    }

    final type = message['type'] as String?;

    if (type == 'auth_ok') {
      _authCompleter?.complete();
      return;
    }

    final requestId = message['requestId'] as String?;
    if (requestId != null && _pending.containsKey(requestId)) {
      final completer = _pending.remove(requestId)!;
      if (type == 'error') {
        completer.completeError(StateError(message['message']?.toString() ?? 'Relay error.'));
      } else {
        completer.complete(message);
      }
      return;
    }

    if (type == 'deliver_packet') {
      _deliveriesController.add(message);
    }
  }

  void _sendRaw(Map<String, dynamic> payload) {
    final data = jsonEncode(payload);
    _channel?.sink.add(data);
  }

  void _failPending(Object error) {
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(error);
      }
    }
    _pending.clear();
  }

  String _requestId() {
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
