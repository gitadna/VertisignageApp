import 'package:flutter/foundation.dart';

/// Drives minimal recovery UI when [value] is true.
class SafeModeGate extends ValueNotifier<bool> {
  SafeModeGate() : super(false);
}
