import 'dart:math';

/// Per-process presentation session id for native Module 4 correlation (not a second playlist cache).
class PresentationSessionManager {
  PresentationSessionManager() : sessionId = _newId();

  final String sessionId;

  static String _newId() {
    final r = Random();
    return 'ps_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 20)}';
  }
}
