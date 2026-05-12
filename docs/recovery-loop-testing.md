# Recovery Loop Hardening - Diagnostics + Validation Checklist

Companion doc for Module 3 final hardening. Use this when validating a new build
on signage panels / TVs / OEM phones to confirm restart-storm dampening and
boot-recovery diagnostics behave correctly. No code lives here; this is the
operational reference for QA + on-call.

## Scope

`RecoveryLoopGuard` only dampens the three full-task **activity relaunch** paths:

- `MainActivity.restartApp` (method channel `restartApp` from Flutter)
- `ScheduleBoundaryAlarmReceiver.restartApplication` (schedule postcheck after a
  failed soft wake)
- `installCrashRestartHandler` activity `PendingIntent` exact alarm

Foreground service, `RecoveryWorker`, `RecoveryAlarmReceiver`, staggered alarm
chain, websocket reconnect, overlays, playback, schedule evaluation, and
`ACTION_WAKE` MUST continue regardless of loop state. If you ever observe one of
those paths blocked, that is a regression.

## Loop Detection Defaults

- Window: 90 seconds
- Threshold: 4 process starts inside the window
- Soft fallback delay applied after suppression: 15 seconds

Do not tighten these without field telemetry first.

## Telemetry Reference (search in remote logs / logcat)

| Event | Meaning |
|-------|---------|
| `recovery_loop_detected` | Edge: device just entered a loop window (sticky until cleared). |
| `recovery_restart_suppressed` | Aggressive relaunch skipped; `path=` distinguishes call site. |
| `recovery_restart_delayed` | Soft fallback armed instead (`delayMs=15000` default). |
| `recovery_loop_cleared` | Edge: device left the loop window naturally. |
| `engine_configure` | `MainActivity.configureFlutterEngine` ran; watch `attachCount` over 24h soak. |
| `soak_heartbeat` | Periodic 15-minute heartbeat with uptime + loop snapshot + engine cache state. |
| `schedule_boundary_alarm_denied` | Exact-alarm permission missing or `SecurityException` at arm time. |
| `schedule_boundary_rearm_burst` | Two `PlaylistScheduleAlarm.schedule` calls within 1s; expected to be rare. |

All telemetry uses `FleetTelemetry.log(...)`; tag `VertiSignageTelemetry` in
logcat, also shipped through `RemoteLogUploader` from Flutter.

## Diagnostics Validation Checklist

### Boot timing deltas

- After a cold boot, expect non-negative `deltaSinceAppOnCreateMs` on
  `activity_oncreate`, `activity_postresume`, `activity_engine_cache_hit`.
- A `-1` value means the corresponding `BootTiming.mark*` was never recorded;
  treat as a missing-event signal, not as real latency.

### Cached FlutterEngine

- Cold install: expect `activity_engine_cache_miss` once, then
  `engine_cache_prewarmed`, then `activity_engine_cache_hit` on the second
  attach.
- Process death + relaunch: expect a single fresh `engine_cache_prewarmed` per
  process; cache hit on first activity attach within the same process.
- `engine_configure attachCount=N` should grow linearly with activity attaches.
  Soak runs that show `attachCount` climbing every minute indicate an unintended
  re-attach loop.

### Staggered alarm chain (boot recovery)

- Inspect logcat for five `recovery_alarm_fallback_staggered` lines at the
  request codes 22101-22105 with `delayMs` 5000 / 15000 / 45000 / 90000 /
  180000.
- The legacy single slot (`22100`) still replaces in place; the five staggered
  slots are intentionally NOT deduped against each other.

### Deferred bootstrap (Flutter)

- Expect a single `flutter_critical_bootstrap_complete` followed by exactly one
  `deferred_bootstrap_started` and one `deferred_bootstrap_complete` per
  process. A second pair would indicate `_deferredDone` was bypassed.
- `websocket_coordinator_started` appears once; `websocket_connected_after_boot`
  appears once with elapsed delta after the first connection.

### BootSplash

- `first_frame_painted` should appear within seconds on warm starts. The splash
  is forced to dismiss after `minimumSplashDuration` once the first frame
  paints, even if `deferredInit` is still running. Verify the underlying
  `AppShell` is interactive once the splash overlay clears.

### Cached engine memory

- Acceptable: one cached engine for the process lifetime.
- Rollback if OEM memory pressure is correlated with the cache: remove
  `provideFlutterEngine` override in `MainActivity`. Telemetry will start
  emitting only `activity_engine_cache_miss` and behavior reverts to cold
  start.

### Lifecycle counters

- `visibleActivities` counter is clamped at 0; the `app_foreground` /
  `app_background` events should alternate without duplicate adjacent entries.

## Restart-Path Stress Tests

| Scenario | Expected behavior |
|----------|------------------|
| Dart loop calling `DeviceService.restartApplication` 6x in 30s | First 1-3 attempts succeed; once threshold is crossed, subsequent calls log `recovery_loop_detected` + `recovery_restart_suppressed`, return `false` to Dart, and arm soft fallback (`restart_loop_soft:restartApp` alarm at +15s). FGS, WM, and websocket remain operational throughout. |
| Schedule postcheck on a hung activity, repeated boundaries | First failing wake triggers `restartApplication`. If 4 process starts accrue within 90s, postcheck switches to `loop_soft`: `schedule_postcheck_loop_soft` FGS ACTION_WAKE + `restart_loop_soft:schedule_postcheck` alarm. Schedule evaluation continues normally. |
| Repeated native crash | `recordNativeCrash` + `RecoveryScheduler.enqueueNow("native_crash")` always run. When in loop, the activity `PendingIntent` alarm is suppressed (no `setExactAndAllowWhileIdle` call); WM + 3s recovery alarm remain. |
| `recovery_loop_cleared` window | After 90s of no new process starts, the next gate call emits `recovery_loop_cleared`; subsequent restarts behave normally. |

## Production Validation Matrix

| Device family | Required scenarios |
|---------------|--------------------|
| Samsung | Cold boot, warm reboot, force-stop, low-memory kill, 24h uptime. |
| Xiaomi (MIUI) | Aggressive auto-start whitelisting, delayed `BOOT_COMPLETED`, staggered alarm fire confirmation. |
| Vivo / iQOO | Background auto-start denial + recovery via alarm chain. |
| Realme / Oppo | App freeze recovery + restartApp suppression. |
| Android TV | Cold boot to first frame, schedule boundary at midnight rollover, overlay recovery after standby. |
| Signage panels | 48h uptime soak, repeated crash simulation, websocket reconnect after WAN drop. |
| Low-RAM (<= 2GB) | Cached engine reuse without OOM, splash dismissal during heavy GC. |

For every device, capture:

1. `boot_received` -> `boot_fgs_started` -> `boot_wake_dispatched` ->
   `boot_fgs_action_wake` -> `activity_postresume` -> `first_frame_painted`
   timeline (sequence + deltas).
2. Five staggered alarm lines in logcat.
3. At least one `soak_heartbeat` confirming uptime, `engineCached=true`,
   `inLoop=false`, fresh `serviceHbAgeMs` / `uiHbAgeMs`.
4. No `recovery_restart_suppressed` event during normal operation; only during
   the explicit stress tests above.

## Rollback Map

| Concern | Rollback action |
|---------|-----------------|
| Loop guard mis-detects normal restarts | Increase `DEFAULT_THRESHOLD` to 6 or `DEFAULT_WINDOW_MS` to 60s in `RecoveryLoopGuard`; revert is one-line. |
| Cached engine memory issue | Remove `provideFlutterEngine` override in `MainActivity`. |
| Staggered alarms too noisy | Comment out `RecoveryScheduler.scheduleBootStaggeredFallbacks` call in `BootReceiver`; legacy 20s alarm remains via `scheduleAlarmFallback` (already replaced by FGS path; restore if needed). |
| Soak heartbeat noise | Remove `emitSoakHeartbeat` call in `RecoveryWorker`; nothing else depends on it. |

Keep changes additive. Every recovery layer must remain independently
disableable.
