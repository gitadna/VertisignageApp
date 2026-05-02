import 'package:flutter/material.dart';

/// Converts CSS-style HSL components (`h s% l%` space-separated) to [Color].
/// [saturation] and [lightness] are **percent** values (e.g. 12 means 12%).
Color cssHsl(double hue, double saturation, double lightness, [double alpha = 1]) {
  return HSLColor.fromAHSL(alpha, hue, saturation / 100, lightness / 100).toColor();
}
