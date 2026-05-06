import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/local_storage.dart';
import '../../../services/device_service.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';

class KioskPermissionsGate extends StatefulWidget {
  const KioskPermissionsGate({super.key, required this.child});

  final Widget child;

  @override
  State<KioskPermissionsGate> createState() => _KioskPermissionsGateState();
}

class _KioskPermissionsGateState extends State<KioskPermissionsGate>
    with WidgetsBindingObserver {
  late final LocalStorage _storage = sl<LocalStorage>();
  late final DeviceService _device = sl<DeviceService>();

  bool _loading = true;
  bool _needsSetup = false;
  bool _overlayOk = false;
  bool _batteryOk = false;
  bool _notificationOk = false;
  /// Device Owner: overlay recommended only. Consumer/sideload: overlay required to continue.
  bool _overlayRequiredForContinue = true;
  int _androidSdk = 0;
  bool _deviceOwner = false;
  bool _bootRecoveryPending = false;
  String? _bootRecoveryReason;
  bool _firstLaunchCompleted = true;

  bool get _notificationsApplicable =>
      Platform.isAndroid && _androidSdk >= 33;

  bool get _canContinue =>
      (_overlayOk || !_overlayRequiredForContinue) &&
      _batteryOk &&
      (!_notificationsApplicable || _notificationOk);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionState());
      unawaited(_kickRecovery('gate_resumed'));
    }
  }

  Future<void> _loadAndroidSdk() async {
    if (!Platform.isAndroid) return;
    final info = await DeviceInfoPlugin().androidInfo;
    if (!mounted) return;
    setState(() => _androidSdk = info.version.sdkInt);
  }

  Future<void> _bootstrap() async {
    if (!Platform.isAndroid) {
      setState(() {
        _loading = false;
        _needsSetup = false;
      });
      return;
    }

    final done =
        _storage.getString(
              StorageKeys.deviceBox,
              StorageKeys.kioskPowerSetupComplete,
            ) ==
            '1';
    if (done) {
      unawaited(_kickRecovery('gate_done_shortcircuit'));
      setState(() {
        _loading = false;
        _needsSetup = false;
      });
      return;
    }

    await _loadAndroidSdk();
    _deviceOwner = await _device.isDeviceOwner();
    _overlayRequiredForContinue = !_deviceOwner;

    await _kickRecovery('gate_bootstrap');

    await _refreshPermissionState(skipSetState: true);
    if (!mounted) return;

    if (_canContinue) {
      await _markComplete();
      setState(() {
        _loading = false;
        _needsSetup = false;
      });
      return;
    }

    setState(() {
      _loading = false;
      _needsSetup = true;
    });
  }

  Future<void> _kickRecovery(String reason) async {
    if (!Platform.isAndroid) return;
    try {
      await _device.recoveryEnsurePeriodic(reason);
      await _device.recoveryEnqueueNow(reason);

      final pending = await _device.getPendingBootRecovery();
      if (!mounted) return;
      setState(() {
        _bootRecoveryPending = (pending['pending'] == true);
        _bootRecoveryReason = pending['reason'] as String?;
        _firstLaunchCompleted = (pending['firstLaunchCompleted'] == true);
      });
    } catch (e) {
      // Never block the gate on recovery diagnostics.
      debugPrint('Recovery kick failed: $e');
    }
  }

  Future<void> _clearBootPending() async {
    try {
      await _device.clearPendingBootRecovery();
    } catch (_) {
      /* ignore */
    }
    if (!mounted) return;
    setState(() {
      _bootRecoveryPending = false;
      _bootRecoveryReason = null;
    });
  }

  Future<String> _getPackageName() async {
    final info = await PackageInfo.fromPlatform();
    return info.packageName;
  }

  Future<void> _refreshPermissionState({bool skipSetState = false}) async {
    final overlay = await Permission.systemAlertWindow.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    bool notification = true;
    if (_notificationsApplicable) {
      notification = await Permission.notification.isGranted;
    }
    if (!mounted) return;
    void apply() {
      _overlayOk = overlay;
      _batteryOk = battery;
      _notificationOk = notification;
    }

    if (skipSetState) {
      apply();
    } else {
      setState(apply);
    }
  }

  Future<void> _markComplete() async {
    await _storage.setString(
      StorageKeys.deviceBox,
      StorageKeys.kioskPowerSetupComplete,
      '1',
    );
  }

  Future<void> _onContinue() async {
    await _refreshPermissionState();
    if (_canContinue) {
      await _markComplete();
      setState(() => _needsSetup = false);
    }
  }

  Future<void> _requestOverlay() async {
    if (!Platform.isAndroid) return;

    try {
      if (await Permission.systemAlertWindow.isGranted) {
        await _refreshPermissionState();
        return;
      }

      final intent = AndroidIntent(
        action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
        data: 'package:${await _getPackageName()}',
      );

      await intent.launch();
    } catch (e) {
      debugPrint('Overlay intent failed: $e');

      await Permission.systemAlertWindow.request();
    }
  }

  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _refreshPermissionState();
  }

  Future<void> _requestNotification() async {
    await Permission.notification.request();
    await _refreshPermissionState();
  }

  Future<void> _openAutoStartSettings() async {
    await _device.openAutoStartSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_needsSetup) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final overlayTitle = _overlayRequiredForContinue
        ? 'Display over other apps'
        : 'Display over other apps (recommended)';
    final overlaySubtitle = _overlayRequiredForContinue
        ? 'Required on this device for native Show on screen and overlay takeover when VertiSignage is not the device-owner kiosk.'
        : 'Managed kiosk mode reduces restrictions; granting this still helps admin Show on screen and overlay announcements if playback leaves lock task.';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Permissions for playback & remote control',
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (_bootRecoveryPending) ...[
                        const SizedBox(height: 12),
                        Card(
                          margin: EdgeInsets.zero,
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Background recovery pending',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _firstLaunchCompleted
                                      ? 'Android reported a reboot/update event; background recovery is attempting to restart the kiosk foreground service.'
                                      : 'This device rebooted or updated before the first app launch. Android does not allow safe auto-start until you open the app once.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (_bootRecoveryReason != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reason: $_bootRecoveryReason',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _clearBootPending,
                                  child: const Text('Dismiss'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Grant these so realtime playlist updates work, admin Take over can bring VertiSignage to the foreground, and Show on screen behaves reliably.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      if (_deviceOwner) ...[
                        const SizedBox(height: 8),
                        Text(
                          'This device is enrolled as device-owner kiosk; fewer limits apply, but battery and notifications below still matter.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      _PermissionRow(
                        title: overlayTitle,
                        subtitle: overlaySubtitle,
                        ok: _overlayOk,
                        requiredForContinue: _overlayRequiredForContinue,
                        onRequest: _requestOverlay,
                      ),
                      const SizedBox(height: 16),
                      _PermissionRow(
                        title: 'Do not optimize battery',
                        subtitle:
                            'Reduces Android suspending the app so WebSocket commands (Take over, volume, sync) still arrive.',
                        ok: _batteryOk,
                        requiredForContinue: true,
                        onRequest: _requestBattery,
                      ),
                      if (_notificationsApplicable) ...[
                        const SizedBox(height: 16),
                        _PermissionRow(
                          title: 'Notifications',
                          subtitle:
                              'Android 13+ requires this for the playback foreground notification; tapping it helps return to the app when it is not visible.',
                          ok: _notificationOk,
                          requiredForContinue: true,
                          requestButtonLabel: 'Allow notifications',
                          onRequest: _requestNotification,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _AutoStartTipCard(
                        onOpenSettings: _openAutoStartSettings,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _canContinue ? _onContinue : null,
                child: const Text('Continue to player'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.requiredForContinue,
    required this.onRequest,
    this.requestButtonLabel = 'Open settings',
  });

  final String title;
  final String subtitle;
  final bool ok;
  final bool requiredForContinue;
  final VoidCallback onRequest;
  final String requestButtonLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (!requiredForContinue)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Recommended',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  ok ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: ok ? Colors.green : theme.colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: ok ? null : onRequest,
              child: Text(ok ? 'Granted' : requestButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoStartTipCard extends StatelessWidget {
  const _AutoStartTipCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Background launch / auto-start',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Recommended — does not block Continue. On Xiaomi, Oppo, Vivo, OnePlus, Samsung and similar builds, admin Take over can fail if background activity or auto-start is restricted. Note: if the user force-stops the app, Android will block auto-start until the app is opened manually.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('Open OEM settings'),
            ),
          ],
        ),
      ),
    );
  }
}
