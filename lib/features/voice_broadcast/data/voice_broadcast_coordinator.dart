import 'dart:async';

import '../../../core/logging/kiosk_log.dart';
import '../../player/data/kiosk_fleet_api.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import 'voice_broadcast_player.dart';
import 'voice_broadcast_models.dart';
import 'voice_broadcast_signaling.dart';

class VoiceBroadcastCoordinator {
  VoiceBroadcastCoordinator({
    required TokenStore tokenStore,
    required VoiceBroadcastSignaling signaling,
    required VoiceBroadcastPlayer player,
    required KioskFleetApi fleetApi,
    required DeviceService deviceService,
  })  : _tokenStore = tokenStore,
        _signaling = signaling,
        _player = player,
        _fleetApi = fleetApi,
        _deviceService = deviceService;

  final TokenStore _tokenStore;
  final VoiceBroadcastSignaling _signaling;
  final VoiceBroadcastPlayer _player;
  final KioskFleetApi _fleetApi;
  final DeviceService _deviceService;
  StreamSubscription? _inviteSub;
  StreamSubscription? _stopSub;
  StreamSubscription? _connectedSub;
  Timer? _fallbackPollTimer;
  bool _started = false;
  bool _joinInFlight = false;

  /// REST fallback when Socket.IO is healthy (invites should cover most cases).
  static const Duration _pollIntervalConnected = Duration(seconds: 22);

  /// Back off active-stream polling when signaling is down to avoid API hammering.
  static const Duration _pollIntervalDisconnected = Duration(seconds: 90);

  /// After a successful socket connection, reconcile with the backend soon.
  static const Duration _pollAfterSocketConnected = Duration(seconds: 8);

  void start() {
    if (_started) return;
    _started = true;
    _tokenStore.addListener(_sync);
    _inviteSub = _signaling.invites.listen((invite) async {
      await _joinSession(invite.streamSessionId);
    });
    _connectedSub = _signaling.connected.listen((_) async {
      KioskLog.event('voice_signal', 'socket_connected_triggering_active_stream_check');
      _schedulePollSoon();
      await _fallbackJoinFromActiveStream(source: 'socket_connected');
    });
    _stopSub = _signaling.stops.listen((_) async {
      await _leaveAndRestoreApp();
      KioskLog.event('voice_signal', 'voice_stream_stopped');
    });
    _restartAdaptivePollChain();
    _sync();
  }

  void _restartAdaptivePollChain() {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer(Duration.zero, () {
      unawaited(_pollTick());
    });
  }

  void _schedulePollSoon() {
    if (!_started) return;
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer(_pollAfterSocketConnected, () {
      unawaited(_pollTick());
    });
  }

  Future<void> _pollTick() async {
    if (!_started) return;
    await _fallbackJoinFromActiveStream(source: 'periodic_poll');
    if (!_started) return;
    final next = _signaling.isSocketConnected ? _pollIntervalConnected : _pollIntervalDisconnected;
    _fallbackPollTimer = Timer(next, () {
      unawaited(_pollTick());
    });
  }

  void _sync() {
    final token = _tokenStore.accessToken;
    final paired = _tokenStore.hasPairedDevice;
    if (paired && token != null && token.isNotEmpty) {
      _signaling.connect();
      return;
    }
    _signaling.disconnect();
    unawaited(_player.leave());
  }

  Future<void> _fallbackJoinFromActiveStream({required String source}) async {
    if (!_started || _joinInFlight) return;
    KioskLog.event('voice_signal', 'active_stream_check_start', meta: <String, Object?>{'source': source});
    final streamSessionId = await _fleetApi.getActiveVoiceStreamSessionId();
    KioskLog.event(
      'voice_signal',
      'active_stream_check_result',
      meta: <String, Object?>{
        'source': source,
        'streamSessionId': streamSessionId,
        'activeSessionId': _player.activeSessionId,
      },
    );
    if (streamSessionId == null) {
      if (_player.activeSessionId != null || _player.hasTakeoverVisible) {
        await _leaveAndRestoreApp();
        KioskLog.event('voice_signal', 'voice_stream_auto_left_no_active_session');
      }
      return;
    }
    if (_player.activeSessionId == streamSessionId) return;
    KioskLog.event('voice_signal', 'fallback_detected_stream', meta: <String, Object?>{'source': source});
    await _joinSession(streamSessionId);
  }

  Future<void> _leaveAndRestoreApp() async {
    await _player.leave();
    await _deviceService.wakeAppToForeground();
  }

  Future<void> _joinSession(String streamSessionId) async {
    if (_joinInFlight) return;
    _joinInFlight = true;
    _player.showPending(streamSessionId);
    try {
      JoinGrant? grant;
      try {
        KioskLog.event('voice_signal', 'join_attempt_socket', meta: <String, Object?>{'streamSessionId': streamSessionId});
        grant = await _signaling.requestJoinBySessionId(streamSessionId);
        KioskLog.event('voice_signal', 'join_success_socket', meta: <String, Object?>{'streamSessionId': streamSessionId});
      } catch (socketError, socketStack) {
        KioskLog.event(
          'voice_signal',
          'join_socket_failed_falling_back_to_rest',
          level: 'error',
          meta: <String, Object?>{
            'streamSessionId': streamSessionId,
            'error': socketError.toString(),
            'stack': socketStack.toString(),
          },
        );
        KioskLog.event('voice_signal', 'join_attempt_rest', meta: <String, Object?>{'streamSessionId': streamSessionId});
        grant = await _fleetApi.requestVoiceJoinGrant(streamSessionId);
        if (grant != null) {
          KioskLog.event('voice_signal', 'join_success_rest', meta: <String, Object?>{'streamSessionId': streamSessionId});
        } else {
          KioskLog.event(
            'voice_signal',
            'join_failed_rest_null_grant',
            level: 'error',
            meta: <String, Object?>{'streamSessionId': streamSessionId},
          );
        }
      }
      if (grant == null) {
        throw StateError('No join grant available from signaling or REST fallback');
      }
      await _player.join(
        streamSessionId: grant.streamSessionId,
        livekitUrl: grant.livekitUrl,
        token: grant.token,
      );
      KioskLog.event('voice_signal', 'voice_stream_joined');
    } catch (e, st) {
      _player.showJoinError(e.toString());
      KioskLog.event(
        'voice_signal',
        'voice_stream_join_failed',
        level: 'error',
        meta: <String, Object?>{
          'error': e.toString(),
          'stack': st.toString(),
          'streamSessionId': streamSessionId,
        },
      );
      KioskLog.e(
        'voice_signal',
        'voice_stream_join_failed error=${e.toString()}\nstack=${st.toString()}',
        st,
      );
    } finally {
      _joinInFlight = false;
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _tokenStore.removeListener(_sync);
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
    await _inviteSub?.cancel();
    _inviteSub = null;
    await _connectedSub?.cancel();
    _connectedSub = null;
    await _stopSub?.cancel();
    _stopSub = null;
    _signaling.disconnect();
    await _player.leave();
  }
}
