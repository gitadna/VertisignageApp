import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/config/environment_config.dart';
import '../../../core/di/injection.dart';
import '../../../core/recovery/kiosk_recovery_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/vertisignage_theme_extension.dart';
import '../../../services/device_service.dart';
import '../../../services/token_store.dart';
import '../data/playlist_sync_service.dart';
import 'emergency_overlay_layer.dart';

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

    if (Platform.isAndroid &&
        sl<EnvironmentConfig>().kioskLockTask &&
        sl<TokenStore>().hasPairedDevice) {
      unawaited(sl<DeviceService>().setLockTaskEnabled(true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            backgroundColor: Colors.black,
            body: Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final tokens = Theme.of(context).extension<VertisignageColors>();
                final mutedIcon = tokens?.textMuted ?? cs.onSurfaceVariant;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.healing_outlined,
                            color: mutedIcon,
                            size: AppSpacing.s12,
                          ),
                          const SizedBox(height: AppSpacing.s6),
                          Text(
                            'Recovery mode',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: cs.onSurface,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.s3),
                          Text(
                            'The app entered recovery after repeated fatal errors. '
                            'Connectivity and fleet commands remain enabled.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          FilledButton(
                            onPressed: () async {
                              await sl<PlaylistSyncService>().sync();
                            },
                            child: const Text('Sync now'),
                          ),
                          const SizedBox(height: AppSpacing.s3),
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
                );
              },
            ),
          ),
          const EmergencyOverlayLayer(),
        ],
      ),
    );
  }
}
