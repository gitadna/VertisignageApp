import 'dart:math';

import '../constants/app_constants.dart';

/// Computes delay for attempt `attemptIndex` (0 = first retry after failure).
Duration computeBackoffDelay({
  required int attemptIndex,
  Duration base = const Duration(milliseconds: 500),
  Duration max = AppConstants.wsReconnectMaxDelay,
  double jitterFactor = 0.2,
}) {
  if (attemptIndex < 0) attemptIndex = 0;
  final expMs = base.inMilliseconds * pow(2, attemptIndex).toInt();
  final capped = expMs > max.inMilliseconds ? max.inMilliseconds : expMs;
  final jitterRange = (capped * jitterFactor).toInt();
  final jitter = jitterRange > 0 ? Random().nextInt(jitterRange) : 0;
  return Duration(milliseconds: capped + jitter);
}
