import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/logging/kiosk_log.dart';
import '../features/player/data/playlist_sync_service.dart';
import '../services/device_service.dart';

class ConnectivityCoordinator {
  ConnectivityCoordinator(this._sync, this._device);

  final PlaylistSyncService _sync;
  final DeviceService _device;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  Timer? _offlineWatchdog;
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
          _offlineWatchdog?.cancel();
          _offlineWatchdog = null;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 1500), () {
            unawaited(_sync.sync());
          });
        } else if (!online) {
          _offlineWatchdog ??= Timer.periodic(const Duration(minutes: 2), (_) {
            unawaited(_device.recoveryEnqueueNow('websocket_offline_watchdog'));
          });
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
    _debounce?.cancel();
    _debounce = null;
    _offlineWatchdog?.cancel();
    _offlineWatchdog = null;
    final s = _sub;
    _sub = null;
    if (s != null) {
      unawaited(s.cancel());
    }
  }
}
