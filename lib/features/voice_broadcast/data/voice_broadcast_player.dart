import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../player/presentation/player_controller.dart';

class VoiceTakeoverUiState {
  const VoiceTakeoverUiState({
    required this.visible,
    required this.streaming,
    required this.message,
  });

  final bool visible;
  final bool streaming;
  final String message;

  static const hidden = VoiceTakeoverUiState(
    visible: false,
    streaming: false,
    message: '',
  );
}

class VoiceBroadcastPlayer {
  VoiceBroadcastPlayer({required PlayerController playerController})
    : _playerController = playerController;

  final PlayerController _playerController;
  Room? _room;
  CancelListenFunc? _roomEventsCancel;
  String? _activeSessionId;
  final ValueNotifier<VoiceTakeoverUiState> takeoverState =
      ValueNotifier<VoiceTakeoverUiState>(VoiceTakeoverUiState.hidden);

  String? get activeSessionId => _activeSessionId;
  bool get hasTakeoverVisible => takeoverState.value.visible;

  void showPending(String streamSessionId) {
    _activeSessionId = streamSessionId;
    _playerController.beginAnnouncementHold();
    takeoverState.value = const VoiceTakeoverUiState(
      visible: true,
      streaming: false,
      message: 'Connecting to live voice stream...',
    );
  }

  void showJoinError(String message) {
    if (!hasTakeoverVisible) return;
    takeoverState.value = VoiceTakeoverUiState(
      visible: true,
      streaming: false,
      message: 'Connection retrying: $message',
    );
  }

  Future<void> join({
    required String streamSessionId,
    required String livekitUrl,
    required String token,
  }) async {
    if (_activeSessionId == streamSessionId && _room != null) return;
    await leave();
    // Prefer loudspeaker for takeover-style voice announcements.
    try {
      await Hardware.instance.setSpeakerphoneOn(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('VoiceBroadcastPlayer speakerphone setup failed: $e');
      }
    }
    if (kDebugMode) {
      debugPrint(
        'VoiceBroadcastPlayer join attempt streamSessionId=$streamSessionId '
        'livekitUrl=$livekitUrl tokenEmpty=${token.trim().isEmpty}',
      );
    }
    final room = Room();
    _roomEventsCancel = room.events.listen((event) {
      if (event is ParticipantConnectedEvent) {
        for (final publication in event.participant.trackPublications.values) {
          if (!publication.subscribed) {
            publication.subscribe();
          }
        }
      }
      if (event is TrackPublishedEvent) {
        final publication = event.publication;
        if (!publication.subscribed) {
          publication.subscribe();
        }
      }
    });
    try {
      await room.connect(livekitUrl, token);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'VoiceBroadcastPlayer room.connect failed livekitUrl=$livekitUrl '
          'tokenEmpty=${token.trim().isEmpty} error=${e.toString()}',
        );
        debugPrint(st.toString());
      }
      throw StateError(
        'LiveKit connect failed (livekitUrl=$livekitUrl, tokenEmpty=${token.trim().isEmpty}): ${e.toString()}',
      );
    }
    _room = room;
    _activeSessionId = streamSessionId;
    _playerController.beginAnnouncementHold();
    takeoverState.value = const VoiceTakeoverUiState(
      visible: true,
      streaming: true,
      message: 'Live voice stream active',
    );
  }

  Future<void> leave() async {
    final room = _room;
    _room = null;
    await _roomEventsCancel?.call();
    _roomEventsCancel = null;
    _activeSessionId = null;
    _playerController.endAnnouncementHold();
    takeoverState.value = VoiceTakeoverUiState.hidden;
    if (room != null) {
      await room.disconnect();
    }
  }
}
