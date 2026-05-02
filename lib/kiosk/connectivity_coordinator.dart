import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/logging/kiosk_log.dart';
import '../features/player/data/playlist_sync_service.dart';

/// Triggers playlist sync when connectivity returns after offline.
class ConnectivityCoordinator {
  ConnectivityCoordinator(this._sync);

  final PlaylistSyncService _sync;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _last = const [ConnectivityResult.none];

  Future<void> start() async {
    try {
      _last = await _connectivity.checkConnectivity();
    } catch (_) {
      _last = const [ConnectivityResult.none];
    }

    await _sub?.cancel();
    _sub = _connectivity.onConnectivityChanged.listen(
      (results) {
        final wasOffline = _wasOffline(_last);
        _last = results;
        final online = _isOnline(results);
        if (wasOffline && online) {
          KioskLog.d('Connectivity', 'back online — sync');
          unawaited(_sync.sync());
        }
      },
      onError: (Object e, StackTrace st) {
        KioskLog.e('Connectivity', e, st);
      },
    );
  }

  bool _wasOffline(List<ConnectivityResult> previous) {
    if (previous.isEmpty) return true;
    return previous.every((r) => r == ConnectivityResult.none);
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    final s = _sub;
    _sub = null;
    if (s != null) {
      unawaited(s.cancel());
    }
  }
}
