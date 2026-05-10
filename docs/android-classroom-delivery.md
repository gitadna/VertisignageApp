# Android classroom delivery (multi-app)

VertiSignage targets **unmanaged teacher tablets** as well as dedicated signage: remote takeover must work while Chrome and other apps stay usable.

## Delivery paths

| Path | Mechanism |
|------|-----------|
| Real-time | High-priority **FCM data** messages handled in `VertiFirebaseMessagingService` → `VertiPushCommandHandler` → overlay or activity wake. |
| Scheduled playlist | In-process Dart `Timer` + optional **native exact alarm** (`PlaylistScheduleAlarm` / `ScheduleBoundaryAlarmReceiver`) when `canScheduleExactAlarms()` is true. |
| Keep-alive | `KioskForegroundService` uses foreground service type **remoteMessaging** (Android 14+); overlay playback uses **mediaPlayback**. |

## Permissions (onboarding)

| Permission | Required to continue | Notes |
|------------|---------------------|--------|
| Display over other apps | Yes (non–Device Owner) | Native takeover over other apps. |
| Battery unrestricted | Yes | Reduces OEM killing the process. |
| Notifications | Yes on API 33+ | Foreground service notification. |
| Exact alarms | No (recommended) | Improves schedule boundary fidelity under Doze; if denied, Dart timers still run while the app process lives. |

## Degraded behavior

- **No overlay**: takeover falls back to bringing `MainActivity` forward (`CommandRelay.wakeApp`).
- **No exact alarms**: playlist boundaries rely on the Dart boundary timer + periodic sync; boundaries may slip under aggressive Doze until the next wake.
- **FGS blocked**: native recovery (`RecoveryWorker`, alarms) attempts restart; logcat tags `VertiSignageBG`, `VertiSignageTelemetry`.

## Device Owner

- **Strict kiosk** (`kioskLockTask`): full lock task via `DeviceOwnerPolicyManager.applyKioskPolicies`.
- **Classroom** (`!kioskLockTask`): `prepareManagedClassroomMode()` calls `applyManagedClassroomPolicies()` (clears strict kiosk restrictions). `MainActivity` does **not** re-enter lock task when relaxed teacher mode is set.

## QA matrix (manual)

Exercise on **Pixel/reference**, **Samsung**, and one **OEM aggressive killer** (Xiaomi / OPPO / Vivo):

| Scenario | Expect |
|----------|--------|
| App in background, Chrome foreground | Push announcement shows overlay or wakes app; native logs `push_announcement_overlay`. |
| Clear all recents | Process may die on some panels; recovery worker / boot paths attempt restart. |
| Deny exact alarms | Playlist still advances via Dart timer; debug log notes native alarm not scheduled. |
| Airplane mode overnight | After reconnect, sync + heartbeat restore; pending pushes may require server retry. |

## Admin / server

- Send **data** payloads with priority high for time-sensitive `vs_cmd` messages (see Firebase Cloud Messaging docs).
- Schedule fidelity improves when the backend emits ticks or playlist updates near window boundaries in addition to client-side timers.

## References

- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Schedule exact alarms](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
- [FCM priority](https://firebase.google.com/docs/cloud-messaging/concept-options#setting-the-priority-of-a-message)
