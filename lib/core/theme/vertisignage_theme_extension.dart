import 'package:flutter/material.dart';

import 'hsl_color.dart';

/// Product-specific tokens matching [`vertisignage/src/index.css`](vertisignage)
/// (`:root` / `.dark`) beyond what [ColorScheme] expresses alone.
@immutable
class VertisignageColors extends ThemeExtension<VertisignageColors> {
  const VertisignageColors({
    required this.psBlue,
    required this.psCyan,
    required this.psOrange,
    required this.psOrangeActive,
    required this.psWarning,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.surfaceDivider,
    required this.textDisplay,
    required this.textBody,
    required this.textSecondary,
    required this.textMuted,
    required this.borderDefault,
    required this.borderInput,
    required this.ring,
  });

  final Color psBlue;
  final Color psCyan;
  final Color psOrange;
  final Color psOrangeActive;
  final Color psWarning;

  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color surfaceDivider;

  final Color textDisplay;
  final Color textBody;
  final Color textSecondary;
  final Color textMuted;

  final Color borderDefault;
  final Color borderInput;

  final Color ring;

  /// Light palette — [`:root`](vertisignage/src/index.css).
  static final VertisignageColors light = VertisignageColors(
    psBlue: cssHsl(0, 0, 12),
    psCyan: cssHsl(0, 0, 26),
    psOrange: cssHsl(24, 95, 50),
    psOrangeActive: cssHsl(24, 85, 38),
    psWarning: cssHsl(0, 75, 55),
    surfacePrimary: cssHsl(0, 0, 100),
    surfaceSecondary: cssHsl(0, 0, 97),
    surfaceDivider: cssHsl(0, 0, 93),
    textDisplay: cssHsl(0, 0, 10),
    textBody: cssHsl(0, 0, 14),
    textSecondary: cssHsl(0, 0, 45),
    textMuted: cssHsl(0, 0, 70),
    borderDefault: cssHsl(0, 0, 86),
    borderInput: cssHsl(0, 0, 90),
    ring: cssHsl(0, 0, 20),
  );

  /// Dark palette — [`.dark`](vertisignage/src/index.css).
  static final VertisignageColors dark = VertisignageColors(
    psBlue: cssHsl(0, 0, 92),
    psCyan: cssHsl(0, 0, 16),
    psOrange: cssHsl(24, 95, 50),
    psOrangeActive: cssHsl(24, 85, 38),
    psWarning: cssHsl(0, 75, 55),
    surfacePrimary: cssHsl(0, 0, 14),
    surfaceSecondary: cssHsl(0, 0, 16),
    surfaceDivider: cssHsl(0, 0, 22),
    textDisplay: cssHsl(0, 0, 98),
    textBody: cssHsl(0, 0, 96),
    textSecondary: cssHsl(0, 0, 72),
    textMuted: cssHsl(0, 0, 55),
    borderDefault: cssHsl(0, 0, 26),
    borderInput: cssHsl(0, 0, 28),
    ring: cssHsl(0, 0, 80),
  );

  @override
  VertisignageColors copyWith({
    Color? psBlue,
    Color? psCyan,
    Color? psOrange,
    Color? psOrangeActive,
    Color? psWarning,
    Color? surfacePrimary,
    Color? surfaceSecondary,
    Color? surfaceDivider,
    Color? textDisplay,
    Color? textBody,
    Color? textSecondary,
    Color? textMuted,
    Color? borderDefault,
    Color? borderInput,
    Color? ring,
  }) {
    return VertisignageColors(
      psBlue: psBlue ?? this.psBlue,
      psCyan: psCyan ?? this.psCyan,
      psOrange: psOrange ?? this.psOrange,
      psOrangeActive: psOrangeActive ?? this.psOrangeActive,
      psWarning: psWarning ?? this.psWarning,
      surfacePrimary: surfacePrimary ?? this.surfacePrimary,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceDivider: surfaceDivider ?? this.surfaceDivider,
      textDisplay: textDisplay ?? this.textDisplay,
      textBody: textBody ?? this.textBody,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      borderDefault: borderDefault ?? this.borderDefault,
      borderInput: borderInput ?? this.borderInput,
      ring: ring ?? this.ring,
    );
  }

  @override
  VertisignageColors lerp(ThemeExtension<VertisignageColors>? other, double t) {
    if (other is! VertisignageColors) return this;
    return VertisignageColors(
      psBlue: Color.lerp(psBlue, other.psBlue, t)!,
      psCyan: Color.lerp(psCyan, other.psCyan, t)!,
      psOrange: Color.lerp(psOrange, other.psOrange, t)!,
      psOrangeActive: Color.lerp(psOrangeActive, other.psOrangeActive, t)!,
      psWarning: Color.lerp(psWarning, other.psWarning, t)!,
      surfacePrimary: Color.lerp(surfacePrimary, other.surfacePrimary, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      surfaceDivider: Color.lerp(surfaceDivider, other.surfaceDivider, t)!,
      textDisplay: Color.lerp(textDisplay, other.textDisplay, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderInput: Color.lerp(borderInput, other.borderInput, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
    );
  }
}
