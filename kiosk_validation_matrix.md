# Kiosk Failure-Injection Validation Matrix

## Acceptance Thresholds
- Max UI downtime after crash/reboot/update: <= 15 seconds.
- Max service recovery latency after kill/task removal: <= 10 seconds.
- Kiosk escape rate during 24h burn-in: 0 escapes.
- Connectivity resync after network recovery: <= 30 seconds.
- Announcement takeover latency p50: <= 3 seconds.
- Announcement takeover latency p95: <= 8 seconds.
- Schedule boundary recovery miss rate during 24h soak: 0 missed boundaries.

## Test Cases
1. Cold reboot with app previously provisioned as Device Owner.
2. Reboot before first manual launch (verify pending recovery messaging and unblock after first launch).
3. Package replace / app update while device is idle.
4. Swipe recent-app task away and verify relaunch + lock task restoration.
5. Simulate runtime crash and verify automatic relaunch.
6. Kill foreground service and verify watchdog restarts service and UI.
7. Disable overlay permission during runtime and verify recovery + gate enforcement.
8. Disable notifications on Android 13+ and verify gate blocks completion.
9. Remove battery optimization exemption and verify gate blocks completion.
10. Keep device offline for 10+ minutes, then restore network and verify sync recovery.
11. Screen-off idle soak (8-24h) with media playback and watchdog checks.
12. OEM background manager intervention on Xiaomi/Vivo/Oppo/Realme/Samsung.
13. Force-stop app from Settings, wait 2 minutes, then send announcement push (expect native fallback path after next manual launch).
14. Enable Battery Saver + Ultra Battery mode (if OEM supports), then send announcement/schedule transition.
15. Revoke auto-start/OEM background launch and verify diagnostics flag degraded survivability mode.
16. Toggle Doze via adb (`dumpsys deviceidle force-idle`) and validate alarm fallback recovery.
17. Disable POST_NOTIFICATIONS on Android 13+ and verify takeover path logs `notification_denied_degraded`.
18. Block background activity launches via OEM setting; confirm native overlay still renders when foreground wake is blocked.

## Multi-Device Registration & Presence (post-fix)
19. **Five unique installs**: Install the APK on five Android devices (mix of physical + emulator). On each, enter a unique pairing code AND the org's enrollment code from admin Settings. Confirm five distinct rows appear in the admin device list and all five remain `online` independently for at least 5 minutes.
20. **Reinstall test**: Uninstall and reinstall the APK on device #2. Confirm pairing screen is required again (no silent fingerprint-recovery into another device's identity) and that other devices stay online throughout.
21. **Duplicate pairing code rejection**: From admin "Add Device", attempt to create a second device row with a pairing code already attached to another device — expect a 409 with a friendly message; no overwrite.
22. **Cross-device claim rejection**: From the kiosk app, enter a pairing code that is currently bound to a different device (different fingerprint) — expect a 409 explaining the code is in use; the original device stays online.
23. **Network-flap debounce**: Toggle Wi-Fi off for ~3 seconds on one paired device. Verify the device row does NOT flicker to `offline`/`online` in admin (debounce holds during the grace period).
24. **Two-org isolation**: With two orgs A and B, confirm a device enrolled with org B's `enrollmentCode` only appears in org B's admin list; org A admin sees nothing.

## Required Evidence Per Test
- Start timestamp and device model/OEM/Android version.
- Service and activity recovery timestamps from logs.
- Takeover path telemetry (`wake_foreground`, `native_overlay_fallback`, `wake_failed_overlay_failed`).
- Screenshot or video proving app remained in kiosk flow.
- Final pass/fail with issue ID for each failure.
