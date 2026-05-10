import '../../../core/logging/kiosk_log.dart';

/// Low-cardinality playback timing for fleet logs (no URLs or asset ids).
abstract final class PlaybackPerfTelemetry {
  static void mediaResolve({
    required bool cacheHit,
    required int elapsedMs,
    required String mediaKindBucket,
  }) {
    KioskLog.event(
      'playback_perf',
      'media_resolve',
      meta: <String, Object?>{
        'cache_hit': cacheHit,
        'media_resolve_ms': elapsedMs,
        'kind': mediaKindBucket,
      },
    );
  }

  static void mediaResolveFailed({required String mediaKindBucket}) {
    KioskLog.event(
      'playback_perf',
      'media_resolve_failed',
      meta: <String, Object?>{'kind': mediaKindBucket},
    );
  }

  static void videoLayerInit({
    required int initMs,
    required int firstFrameMs,
    required bool networkSource,
  }) {
    KioskLog.event(
      'playback_perf',
      'video_layer_init',
      meta: <String, Object?>{
        'video_init_ms': initMs,
        'first_frame_ms': firstFrameMs,
        'network': networkSource,
      },
    );
  }

  static void prefetchRound({
    required int itemCount,
    required int elapsedMs,
    required int readyCount,
  }) {
    KioskLog.event(
      'playback_perf',
      'prefetch_round',
      meta: <String, Object?>{
        'prefetch_round_ms': elapsedMs,
        'item_count': itemCount,
        'ready_count': readyCount,
      },
    );
  }

  static void moveTaskToBackDenied() {
    KioskLog.event(
      'playback_perf',
      'move_task_to_back_denied',
      meta: const <String, Object?>{},
    );
  }
}
