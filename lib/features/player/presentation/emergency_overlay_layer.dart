import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/emergency_overlay_notifier.dart';

/// Full-screen emergency message when [EmergencyOverlayNotifier] is active.
/// Expects a dark [Theme] ancestor (see [AppTheme.dark]) for kiosk chrome parity.
class EmergencyOverlayLayer extends StatelessWidget {
  const EmergencyOverlayLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sl<EmergencyOverlayNotifier>(),
      builder: (context, _) {
        final notifier = sl<EmergencyOverlayNotifier>();
        if (!notifier.isActive) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: AppSpacing.kioskOverlayOpacity),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      notifier.title ?? 'Alert',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      notifier.message ?? '',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface,
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
    );
  }
}
