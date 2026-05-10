import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../../core/config/environment_config.dart';
import '../../../core/logging/kiosk_log.dart';
import '../../../services/token_store.dart';
import 'voice_broadcast_models.dart';

class VoiceBroadcastSignaling {
  VoiceBroadcastSignaling({
    required TokenStore tokenStore,
    required EnvironmentConfig env,
  })  : _tokenStore = tokenStore,
        _env = env;

  final TokenStore _tokenStore;
  final EnvironmentConfig _env;
  sio.Socket? _socket;
  final StreamController<StreamInviteEnvelope> _invitesController =
      StreamController<StreamInviteEnvelope>.broadcast();
  final StreamController<String> _stopsController =
      StreamController<String>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();

  DateTime? _lastConnectErrorLoggedAt;
  String? _lastConnectErrorDigest;

  Stream<StreamInviteEnvelope> get invites => _invitesController.stream;
  Stream<String> get stops => _stopsController.stream;
  Stream<void> get connected => _connectedController.stream;

  /// True when Socket.IO reports an active connection (used to slow REST fallback polling when down).
  bool get isSocketConnected => _socket?.connected ?? false;

  String _socketBaseUrl() {
    final raw = _env.apiBaseUrl.trim();
    if (raw.endsWith('/api')) {
      return raw.substring(0, raw.length - 4);
    }
    if (raw.endsWith('/api/')) {
      return raw.substring(0, raw.length - 5);
    }
    return raw;
  }

  void _maybeLogConnectError(dynamic err) {
    final now = DateTime.now();
    final digest = err.toString();
    final lastAt = _lastConnectErrorLoggedAt;
    if (lastAt != null &&
        digest == _lastConnectErrorDigest &&
        now.difference(lastAt) < const Duration(seconds: 45)) {
      return;
    }
    _lastConnectErrorLoggedAt = now;
    _lastConnectErrorDigest = digest;
    KioskLog.w('voice_signal', 'socket_connect_error: $digest');
  }

  void connect() {
    if (_socket != null) return;
    final token = _tokenStore.accessToken;
    if (token == null || token.isEmpty) return;

    final socket = sio.io(
      _socketBaseUrl(),
      sio.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .setAuth(<String, dynamic>{'token': token})
          .setExtraHeaders(<String, dynamic>{
            'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
          })
          .enableReconnection()
          .setReconnectionAttempts(48)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(60000)
          .setRandomizationFactor(0.5)
          .build(),
    );
    socket.onConnect((_) {
      KioskLog.event('voice_signal', 'socket_connected');
      _connectedController.add(null);
    });
    socket.onDisconnect((_) {
      KioskLog.event('voice_signal', 'socket_disconnected');
    });
    socket.onConnectError((dynamic err) {
      _maybeLogConnectError(err);
    });
    socket.on('stream:invite', (dynamic data) {
      KioskLog.event(
        'voice_signal',
        'stream_invite_socket_event',
        meta: <String, Object?>{'payloadType': data.runtimeType.toString()},
      );
      if (data is Map) {
        KioskLog.event('voice_signal', 'stream_invite_received');
        _invitesController.add(
          StreamInviteEnvelope.fromMap(Map<String, dynamic>.from(data)),
        );
      }
    });
    socket.on('stream:stop', (dynamic data) {
      if (data is Map) {
        final payload = data['payload'];
        final reason = payload is Map ? payload['reason']?.toString() : null;
        _stopsController.add(reason ?? 'stopped');
      }
    });
    _socket = socket;
  }

  Future<JoinGrant> requestJoin(StreamInviteEnvelope invite) {
    return requestJoinBySessionId(invite.streamSessionId);
  }

  Future<JoinGrant> requestJoinBySessionId(String streamSessionId) {
    final completer = Completer<JoinGrant>();
    final socket = _socket;
    if (socket == null) {
      completer.completeError(StateError('Socket is not connected'));
      return completer.future;
    }

    socket.emitWithAck(
      'stream:join:request',
      <String, dynamic>{
        'streamSessionId': streamSessionId,
        'appState': 'foreground',
      },
      ack: (dynamic response) {
        final map = Map<String, dynamic>.from(response as Map);
        final ok = map['ok'] == true;
        if (!ok) {
          KioskLog.event(
            'voice_signal',
            'stream_join_rejected',
            level: 'error',
            meta: <String, Object?>{'error': map['error']?.toString()},
          );
          completer.completeError(StateError((map['error'] ?? 'Join failed').toString()));
          return;
        }
        final data = Map<String, dynamic>.from(map['data'] as Map);
        KioskLog.event('voice_signal', 'stream_join_granted');
        completer.complete(JoinGrant.fromMap(data));
      },
    );
    Future<void>.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError(StateError('stream:join:request ack timeout'));
      }
    });

    return completer.future;
  }

  void disconnect() {
    _lastConnectErrorLoggedAt = null;
    _lastConnectErrorDigest = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  Future<void> dispose() async {
    disconnect();
    await _invitesController.close();
    await _stopsController.close();
    await _connectedController.close();
  }
}
