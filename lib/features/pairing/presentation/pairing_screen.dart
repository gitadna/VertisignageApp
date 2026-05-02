import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/vertisignage_theme_extension.dart';
import 'pairing_controller.dart';

/// Pairing form — delegates actions to [PairingController] only.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.controller});

  final PairingController controller;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final horizontal = mq.width >= 600
        ? AppSpacing.containerHorizontal
        : AppSpacing.s6;
    final tokens = Theme.of(context).extension<VertisignageColors>();
    final secondary = tokens?.textSecondary ??
        Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final c = widget.controller;
                  final loading = c.phase == PairingPhase.loading;

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: Column(
                      key: ValueKey(loading),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pair device',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          'Enter the pairing code from your Vertisignage console.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: secondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        TextField(
                          controller: _codeController,
                          enabled: !loading,
                          decoration: const InputDecoration(
                            labelText: 'Pairing code',
                          ),
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted:
                              loading ? null : (_) => c.submit(_codeController.text),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        FilledButton(
                          onPressed: loading
                              ? null
                              : () => c.submit(_codeController.text),
                          child: const Text('Pair'),
                        ),
                        if (loading) ...[
                          const SizedBox(height: AppSpacing.s6),
                          const Center(child: CircularProgressIndicator()),
                        ],
                        if (c.phase == PairingPhase.error &&
                            c.errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            c.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
