  import 'dart:async';
  import 'dart:io';

  import 'package:flutter/material.dart';
  import 'package:permission_handler/permission_handler.dart';

  import '../../../core/constants/storage_keys.dart';
  import '../../../core/di/injection.dart';
  import '../../../core/storage/local_storage.dart';
  import 'package:android_intent_plus/android_intent.dart';
  import 'package:flutter/foundation.dart';
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

    bool _loading = true;
    bool _needsSetup = false;
    bool _overlayOk = false;
    bool _batteryOk = false;

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
      }
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
        setState(() {
          _loading = false;
          _needsSetup = false;
        });
        return;
      }

      await _refreshPermissionState();
      if (_overlayOk && _batteryOk) {
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

    Future<String> _getPackageName() async {
    final info = await PackageInfo.fromPlatform();
    return info.packageName;
    }

    Future<void> _refreshPermissionState() async {
      final overlay = await Permission.systemAlertWindow.isGranted;
      final battery = await Permission.ignoreBatteryOptimizations.isGranted;
      if (!mounted) return;
      setState(() {
        _overlayOk = overlay;
        _batteryOk = battery;
      });
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
      if (_overlayOk && _batteryOk) {
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

    // Fallback to permission_handler
    await Permission.systemAlertWindow.request();
  }
  }

    Future<void> _requestBattery() async {
      await Permission.ignoreBatteryOptimizations.request();
      await _refreshPermissionState();
    }

    @override
    Widget build(BuildContext context) {
      if (_loading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (!_needsSetup) {
        return widget.child;
      }

      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reliable playback',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Grant these once so the player can draw over other apps and stay reachable when schedules or media change in realtime.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                _PermissionRow(
                  title: 'Display over other apps',
                  subtitle:
                      'Lets alerts and kiosk overlays appear when another app is in front.',
                  ok: _overlayOk,
                  onRequest: _requestOverlay,
                ),
                const SizedBox(height: 16),
                _PermissionRow(
                  title: 'Do not optimize battery',
                  subtitle:
                      'Reduces Android suspending the app so playlist pushes and remote commands still arrive.',
                  ok: _batteryOk,
                  onRequest: _requestBattery,
                ),
                const Spacer(),
                FilledButton(
                  onPressed: (_overlayOk && _batteryOk) ? _onContinue : null,
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
      required this.onRequest,
    });

    final String title;
    final String subtitle;
    final bool ok;
    final VoidCallback onRequest;

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
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
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
                child: Text(ok ? 'Granted' : 'Open settings'),
              ),
            ],
          ),
        ),
      );
    }
  } 