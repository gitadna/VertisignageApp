import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/recovery/kiosk_recovery_store.dart';
import '../../../core/websocket/realtime_client.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import '../data/emergency_overlay_notifier.dart';
import '../data/playlist_sync_service.dart';
import '../data/realtime_dispatcher.dart';

/// Minimal UI when crash threshold triggers safe mode — still runs sync + WebSocket.
class SafeModeScreen extends StatefulWidget {
  const SafeModeScreen({super.key});

  @override
  State<SafeModeScreen> createState() => _SafeModeScreenState();
}

class _SafeModeScreenState extends State<SafeModeScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await sl<PlaylistSyncService>().bootstrap();
    if (!mounted) return;

    sl<RealtimeDispatcher>().ensureStarted();
    unawaited(sl<RealtimeClient>().connect());

    if (!mounted) return;

    if (Platform.isAndroid &&
        sl<EnvironmentConfig>().kioskLockTask &&
        sl<TokenStore>().hasPairedDevice) {
      unawaited(sl<DeviceService>().setLockTaskEnabled(true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.healing, color: Colors.white54, size: 48),
                    const SizedBox(height: 24),
                    Text(
                      'Recovery mode',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The app entered recovery after repeated fatal errors. '
                      'Connectivity and fleet commands remain enabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () async {
                        await sl<PlaylistSyncService>().sync();
                      },
                      child: const Text('Sync now'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        await sl<KioskRecoveryStore>().clearSafeMode();
                      },
                      child: const Text('Exit recovery'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: sl<EmergencyOverlayNotifier>(),
          builder: (context, _) {
            final overlay = sl<EmergencyOverlayNotifier>();
            if (!overlay.isActive) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: Material(
                color: Colors.black.withOpacity(0.85),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          overlay.title ?? 'Alert',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          overlay.message ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
