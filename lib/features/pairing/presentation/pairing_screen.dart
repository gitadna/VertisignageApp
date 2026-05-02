import 'package:flutter/material.dart';

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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final c = widget.controller;
              final loading = c.phase == PairingPhase.loading;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: _codeController,
                    enabled: !loading,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: loading ? null : (_) => c.submit(_codeController.text),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: loading
                        ? null
                        : () => c.submit(_codeController.text),
                    child: const Text('Pair'),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (c.phase == PairingPhase.error &&
                      c.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      c.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
