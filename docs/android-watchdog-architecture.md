# Android watchdog & recovery architecture (production)

Goal: keep VertiSignage responsive across OEM-kill devices **without changing playback/overlay/schedule semantics**. System uses layered recovery so any single mechanism failing still recovers.

## Core components (native)

- **Boot recovery**: `BootReceiver`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/BootReceiver.kt`
  - Triggers: `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON`
  - Behavior:
    - Dedupe rapid boot broadcasts (10s window)
    - Gate: does nothing until Flutter marks `first_launch_completed`
    - Schedules recovery: `RecoveryScheduler.ensurePeriodic/enqueueNow/scheduleAlarmFallback`
    - Starts `KioskForegroundService` via `startForegroundService`
    - Best-effort wake: `CommandRelay.wakeApp`

- **Foreground keep-alive**: `KioskForegroundService`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/KioskForegroundService.kt`
  - Type: `FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING`
  - Behavior:
    - Promotes to foreground with ongoing notification
    - Holds a **partial wakelock** (bounded timeout)
    - Marks service heartbeat (`WatchdogState`)
    - On key events schedules recovery and alarm fallback
    - Handles `ACTION_WAKE` to bring UI to foreground via `CommandRelay.wakeApp` (BAL-friendly path)

- **Periodic watchdog**: WorkManager `RecoveryWorker`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/RecoveryWorker.kt`
  - Cadence: 15 min periodic (minimum), plus one-shot enqueues
  - Behavior:
    - Reads `WatchdogState` last UI/service heartbeats
    - Restarts `KioskForegroundService` if stale
    - Optionally brings UI forward if stale and `ForegroundWakeGuard` allows
    - Schedules alarm fallback for redundancy

- **Alarm fallback**: `RecoveryAlarmReceiver`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/RecoveryAlarmReceiver.kt`
  - Mechanism: `AlarmManager.RTC_WAKEUP setAndAllowWhileIdle`
  - Behavior:
    - Enqueues `RecoveryWorker` and tries to start `KioskForegroundService`
    - Does **not** directly bring `MainActivity` forward (worker applies guard)

- **Crash restart (native)**: uncaught exception handler
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/MainActivity.kt`
  - Behavior:
    - Writes crash marker (`WatchdogState.recordNativeCrash`)
    - Enqueues `RecoveryWorker` + alarm fallback
    - Schedules exact relaunch `PendingIntent.getActivity` after ~2s

## Core components (Flutter)

- **Post bootstrap wiring**: `KioskPostBootstrap.configure`
  - File: `app/lib/kiosk/kiosk_post_bootstrap.dart`
  - Behavior (Android):
    - Marks `first_launch_completed` (enables boot receiver auto-start)
    - Ensures periodic recovery (`recoveryEnsurePeriodic`)
    - Starts native FGS notification (`startForegroundNotification`)
    - Starts realtime coordinators (websocket, voice, push registration)
    - Starts `ForegroundPresentationCoordinator`

- **Foreground intent + minimize policy**: `ForegroundPresentationCoordinator`
  - File: `app/lib/kiosk/foreground_presentation_coordinator.dart`
  - Signals native `presentationWantsForeground` via `syncForegroundPresentationState`
  - Uses wakelock when playing/announcements/emergency/voice takeover active
  - When non-lock-task (teacher/classroom), can `moveTaskToBack` after playback ends

- **Schedule boundary**: Dart timer + native exact alarm belt
  - Flutter: `PlaylistSyncService._scheduleBoundaryTimer`
    - File: `app/lib/features/player/data/playlist_sync_service.dart`
    - On boundary: `sync(forceCommit: true, minimizeAfterBoundary: true)`
    - Also kicks recovery: `recoveryEnqueueNow('schedule_boundary_*')`
  - Native: `PlaylistScheduleAlarm` + `ScheduleBoundaryAlarmReceiver`
    - Files:
      - `app/android/app/src/main/kotlin/com/example/vertisignage/PlaylistScheduleAlarm.kt`
      - `app/android/app/src/main/kotlin/com/example/vertisignage/ScheduleBoundaryAlarmReceiver.kt`
    - Exact alarm is best-effort (may be denied on Android 12+)
    - On fire: sync presentation state, enqueue recovery, try start FGS

- **Realtime takeover**: `RealtimeDispatcher`
  - File: `app/lib/features/player/data/realtime_dispatcher.dart`
  - Behavior:
    - For push/announcement: tries `wakeAppToForeground` then waits for `resumed`
    - If cannot foreground, falls back to native overlay (`DeviceService.showOverlay`)
    - After overlay/push ends (non-lock-task): can minimize via `moveTaskToBack`

## Push/overlay when Flutter dead (native path)

- Entry: `VertiFirebaseMessagingService.onMessageReceived`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/VertiFirebaseMessagingService.kt`
  - If `vs_cmd` handled by `VertiPushCommandHandler`, Flutter pipeline is bypassed.

- Command handler: `VertiPushCommandHandler`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/VertiPushCommandHandler.kt`
  - Fetches full announcement JSON (using stored API/token/deviceId from `PushContextStore`)
  - Shows native overlay (and optionally wakes UI) even if Flutter engine not running

- Renderer: `OverlayWindowService`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/OverlayWindowService.kt`
  - Foreground service type: `mediaPlayback`
  - Full-screen overlay via `TYPE_APPLICATION_OVERLAY`

## Guardrails: “don’t steal focus” in classroom mode

- Persisted policy: `ForegroundWakePolicy`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/ForegroundWakePolicy.kt`
  - Stores:
    - `relaxed_teacher_mode`
    - `presentation_wants_foreground`
    - `user_backdrop_since_ms` (Home/task switch hint)

- Wake gating: `ForegroundWakeGuard`
  - File: `app/android/app/src/main/kotlin/com/example/vertisignage/ForegroundWakeGuard.kt`
  - If relaxed mode + user backdrop + Flutter says “no foreground”, watchdog avoids bringing app to front.

## Reason codes (used in recovery telemetry)

Native/Flutter call sites pass reason strings into `RecoveryScheduler.enqueueNow/ensurePeriodic` and alarm fallback.

Common reasons (non-exhaustive):
- `boot:<ACTION>`
- `boot_pending_first_launch:<ACTION>`
- `boot_fgs_start_blocked:<ACTION>`
- `activity_post_resume`
- `service_create`
- `service_start_command:<action|null>`
- `service_task_removed`
- `native_crash`
- `overlay_permission_missing*`
- `overlay_add_view_failed`
- `push_*` (native FCM takeover)
- `schedule_exact_boundary` (native exact alarm fired)
- `schedule_boundary_hit|edge|retry` (Dart boundary timer)

## Operational notes

- **Android 13+ notifications**: denying `POST_NOTIFICATIONS` can break/limit FGS visibility and persistence.
- **Exact alarms**: recommended on Android 12+ for schedule fidelity; if denied, Dart timers still work only while process remains alive.
- **OEM auto-start**: required on many Xiaomi/Vivo/Oppo/Realme builds for reliable reboot/update recovery.

