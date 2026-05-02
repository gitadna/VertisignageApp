import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/di/injection.dart';
import '../../../core/recovery/safe_mode_gate.dart';
import '../../../services/token_store.dart';
import '../../pairing/presentation/pairing_controller.dart';
import '../../pairing/presentation/pairing_screen.dart';
import '../../player/presentation/player_controller.dart';
import '../../player/presentation/player_screen.dart';
import '../../player/presentation/safe_mode_screen.dart';

/// Single-home gate: pairing vs player when paired (no routes).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  PairingController? _pairingController;

  late final TokenStore _tokenStore = sl<TokenStore>();

  @override
  void initState() {
    super.initState();
    _tokenStore.addListener(_onTokenStoreChanged);
    if (!_tokenStore.hasPairedDevice) {
      _pairingController = sl<PairingController>()..addListener(_onPairingChanged);
    }
  }

  void _onTokenStoreChanged() {
    setState(() {});
    if (!_tokenStore.hasPairedDevice && _pairingController == null) {
      _pairingController = sl<PairingController>()..addListener(_onPairingChanged);
    }
  }

  void _onPairingChanged() {
    setState(() {});
    final store = _tokenStore;
    if (_pairingController != null && store.hasPairedDevice) {
      final toDispose = _pairingController!;
      toDispose.removeListener(_onPairingChanged);
      _pairingController = null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        toDispose.dispose();
      });
    }
  }

  @override
  void dispose() {
    _tokenStore.removeListener(_onTokenStoreChanged);
    final c = _pairingController;
    if (c != null) {
      c.removeListener(_onPairingChanged);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = _tokenStore;
    final gate = sl<SafeModeGate>();

    return ListenableBuilder(
      listenable: gate,
      builder: (context, _) {
        if (store.hasPairedDevice && gate.value) {
          return const SafeModeScreen();
        }
        if (store.hasPairedDevice) {
          return PlayerScreen(controller: sl<PlayerController>());
        }

        final c = _pairingController;
        if (c == null) {
          return const Scaffold(body: SizedBox.shrink());
        }

        return PairingScreen(controller: c);
      },
    );
  }
}
