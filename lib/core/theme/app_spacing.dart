/// Tailwind-aligned spacing (default scale: 4px base).
abstract final class AppSpacing {
  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;

  /// Horizontal padding matching web container `2rem` (32px at 16px root).
  static const double containerHorizontal = s8;

  /// [`index.css`](vertisignage) `--radius` = 0.75rem.
  static const double radiusLg = 12;

  /// `rounded-md` in Tailwind config: `calc(var(--radius) - 2px)`.
  static const double radiusMd = 10;

  /// `rounded-sm`: `calc(var(--radius) - 4px)`.
  static const double radiusSm = 8;

  /// Full-screen kiosk overlay scrim (product chrome; not from CSS tokens).
  static const double kioskOverlayOpacity = 0.85;

  /// Minimum touch target for kiosk (Material guideline).
  static const double minTouchTarget = 48;
}
