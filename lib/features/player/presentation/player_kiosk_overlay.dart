import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';

/// Minimal bottom chrome for kiosk playback: transport + device actions.
/// Parent owns visibility and auto-hide timing so this stays a cheap subtree.
class PlayerKioskOverlay extends StatelessWidget {
  const PlayerKioskOverlay({
    super.key,
    required this.isPaused,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onClearCache,
    required this.onResetApp,
    required this.onRepair,
    required this.onStartupDiagnostics,
    required this.onInteract,
  });

  final bool isPaused;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClearCache;
  final VoidCallback onResetApp;
  final VoidCallback onRepair;
  final VoidCallback onStartupDiagnostics;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s2,
          AppSpacing.s4,
          AppSpacing.s4,
        ),
        child: Material(
          color: Colors.black,
          borderRadius: BorderRadius.circular(AppSpacing.s3),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onInteract,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous',
                        onPressed: () {
                          onInteract();
                          onPrevious();
                        },
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          color: cs.onSurface,
                        ),
                      ),
                      IconButton(
                        tooltip: isPaused ? 'Play' : 'Pause',
                        onPressed: () {
                          onInteract();
                          onPlayPause();
                        },
                        icon: Icon(
                          isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: cs.onSurface,
                          size: 32,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        onPressed: () {
                          onInteract();
                          onNext();
                        },
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.s1,
                    runSpacing: AppSpacing.s1,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          onInteract();
                          onStartupDiagnostics();
                        },
                        icon: Icon(
                          Icons.health_and_safety_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        label: Text(
                          'Startup check',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
