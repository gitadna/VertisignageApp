import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/di/injection.dart';
import '../../../services/token_store.dart';
import '../../pairing/presentation/pairing_controller.dart';
import '../../pairing/presentation/pairing_screen.dart';
import '../../player/presentation/player_controller.dart';
import '../../player/presentation/player_screen.dart';

/// Single-home gate: pairing vs player when paired (no routes).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  PairingController? _pairingController;

  @override
  void initState() {
    super.initState();
    if (!sl<TokenStore>().hasPairedDevice) {
      _pairingController = sl<PairingController>()..addListener(_onPairingChanged);
    }
  }

  void _onPairingChanged() {
    setState(() {});
    final store = sl<TokenStore>();
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
    final c = _pairingController;
    if (c != null) {
      c.removeListener(_onPairingChanged);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = sl<TokenStore>();
    if (store.hasPairedDevice) {
      return PlayerScreen(controller: sl<PlayerController>());
    }

    final c = _pairingController;
    if (c == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return PairingScreen(controller: c);
  }
}
