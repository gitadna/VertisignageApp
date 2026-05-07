import 'package:flutter_test/flutter_test.dart';
import 'package:vertisignage/core/websocket/realtime_command.dart';

void main() {
  group('parseRealtimeCommand', () {
    test('parses PLAYLIST_UPDATED', () {
      final cmd = parseRealtimeCommand(
        '{"type":"PLAYLIST_UPDATED","payload":{"playlistId":"p1"}}',
      );
      expect(cmd, isA<PlaylistUpdatedCommand>());
      expect((cmd as PlaylistUpdatedCommand).playlistId, 'p1');
    });

    test('parses EMERGENCY_ALERT', () {
      final cmd = parseRealtimeCommand(
        '{"type":"EMERGENCY_ALERT","payload":{"alertId":"a","alertType":"fire","title":"t","message":"m"}}',
      );
      expect(cmd, isA<EmergencyAlertCommand>());
    });

    test('parses VOLUME_SET', () {
      final cmd = parseRealtimeCommand(
        '{"type":"VOLUME_SET","payload":{"volume":42}}',
      );
      expect(cmd, isA<VolumeSetCommand>());
      expect((cmd as VolumeSetCommand).volume, 42);
    });

    test('parses UPDATE_APP', () {
      final cmd = parseRealtimeCommand(
        '{"type":"UPDATE_APP","payload":{"messageId":"m","url":"https://x/apk","sha256":"abc","version":"1.0"}}',
      );
      expect(cmd, isA<UpdateAppCommand>());
      final u = cmd as UpdateAppCommand;
      expect(u.messageId, 'm');
      expect(u.url, 'https://x/apk');
    });

    test('returns null for unknown type', () {
      expect(parseRealtimeCommand('{"type":"UNKNOWN"}'), isNull);
    });

    test('parses ANNOUNCEMENT scheduleEndsAt', () {
      final cmd = parseRealtimeCommand(
        '{"type":"ANNOUNCEMENT","payload":{"announcementId":"a1","title":"T","durationSec":15,"scheduleEndsAt":"2026-05-05T18:00:00.000Z"}}',
      );
      expect(cmd, isA<AnnouncementCommand>());
      final a = cmd as AnnouncementCommand;
      expect(a.scheduleEndsAtUtc?.toIso8601String(), '2026-05-05T18:00:00.000Z');
    });

    test('parses ANNOUNCEMENT resumePreviousPlayback flag', () {
      final cmd = parseRealtimeCommand(
        '{"type":"ANNOUNCEMENT","payload":{"announcementId":"a1","title":"T","durationSec":15,"resumePreviousPlayback":true}}',
      );
      expect(cmd, isA<AnnouncementCommand>());
      final a = cmd as AnnouncementCommand;
      expect(a.resumePreviousPlayback, isTrue);
    });

    test('parses OVERLAY_SHOW resumePreviousPlayback flag', () {
      final cmd = parseRealtimeCommand(
        '{"type":"OVERLAY_SHOW","payload":{"messageId":"m1","text":"hello","resumePreviousPlayback":true}}',
      );
      expect(cmd, isA<OverlayShowCommand>());
      final o = cmd as OverlayShowCommand;
      expect(o.resumePreviousPlayback, isTrue);
    });
  });
}
