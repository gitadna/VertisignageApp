import '../../../models/playlist_bundle.dart';

/// Lightweight playback/sync snapshot for heartbeats (no UI coupling).
class PlayerTelemetry {
  DateTime? lastSuccessfulSyncUtc;
  DateTime? lastSyncAttemptUtc;
  bool lastSyncOk = true;
  String syncStatus = 'idle';
  String? currentPlaylistId;
  String? currentScheduleId;

  void markSyncStarted() {
    syncStatus = 'syncing';
    lastSyncAttemptUtc = DateTime.now().toUtc();
  }

  void markSyncOutcome({
    required bool ok,
    PlaylistBundle? bundle,
  }) {
    lastSyncAttemptUtc = DateTime.now().toUtc();
    lastSyncOk = ok;
    syncStatus = ok ? 'idle' : 'error';
    if (ok) {
      lastSuccessfulSyncUtc = lastSyncAttemptUtc;
      if (bundle != null) {
        currentPlaylistId = bundle.schedule?.playlistId;
        currentScheduleId = bundle.schedule?.scheduleId;
      }
    }
  }
}
