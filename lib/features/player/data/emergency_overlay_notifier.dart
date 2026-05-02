import 'package:flutter/foundation.dart';

/// Placeholder for full-screen emergency UI; wire from [RealtimeDispatcher].
class EmergencyOverlayNotifier extends ChangeNotifier {
  String? _alertId;
  String? _title;
  String? _message;

  String? get alertId => _alertId;
  String? get title => _title;
  String? get message => _message;

  bool get isActive => _alertId != null;

  void show({
    required String alertId,
    required String title,
    required String message,
  }) {
    _alertId = alertId;
    _title = title;
    _message = message;
    notifyListeners();
  }

  void clear(String resolvedAlertId) {
    if (_alertId == resolvedAlertId) {
      _alertId = null;
      _title = null;
      _message = null;
      notifyListeners();
    }
  }

  void clearAny() {
    _alertId = null;
    _title = null;
    _message = null;
    notifyListeners();
  }
}
