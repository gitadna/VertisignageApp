import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_spacing.dart';
import 'hsl_color.dart';
import 'vertisignage_theme_extension.dart';

/// Vertisignage app themes aligned with [`vertisignage/src/index.css`](vertisignage).
abstract final class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        tokens: VertisignageColors.light,
      );

  /// Dark tokens for kiosk chrome (recovery, emergency overlay). Playback stays black.
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        tokens: VertisignageColors.dark,
      );

  static double _emLetterSpacing(double? fontSize) => -0.01 * (fontSize ?? 14);

  static ColorScheme _colorScheme(Brightness brightness, VertisignageColors v) {
    final onPrimaryLight = cssHsl(0, 0, 98);
    final onPrimaryDark = cssHsl(0, 0, 12);
    final accentFg = cssHsl(0, 0, 98);

    if (brightness == Brightness.light) {
      return ColorScheme(
        brightness: Brightness.light,
        primary: v.psBlue,
        onPrimary: onPrimaryLight,
        primaryContainer: v.surfaceDivider,
        onPrimaryContainer: v.textBody,
        secondary: v.surfaceDivider,
        onSecondary: v.textBody,
        secondaryContainer: v.surfacePrimary,
        onSecondaryContainer: v.textBody,
        tertiary: v.psCyan,
        onTertiary: accentFg,
        error: v.psWarning,
        onError: onPrimaryLight,
        surface: v.surfaceSecondary,
        onSurface: v.textBody,
        onSurfaceVariant: v.textSecondary,
        outline: v.borderDefault,
        outlineVariant: v.borderInput,
        shadow: cssHsl(0, 0, 0, 0.12),
        scrim: cssHsl(0, 0, 0, 0.45),
        inverseSurface: v.textBody,
        onInverseSurface: v.surfacePrimary,
        inversePrimary: v.psBlue,
        surfaceContainerHighest: v.surfacePrimary,
        surfaceContainerHigh: v.surfacePrimary,
        surfaceContainer: v.surfaceDivider,
        surfaceContainerLow: v.surfaceSecondary,
        surfaceContainerLowest: v.surfaceSecondary,
        surfaceTint: Colors.transparent,
      );
    }

    return ColorScheme(
      brightness: Brightness.dark,
      primary: cssHsl(0, 0, 96),
      onPrimary: onPrimaryDark,
      primaryContainer: v.surfaceDivider,
      onPrimaryContainer: v.textBody,
      secondary: v.surfaceDivider,
      onSecondary: v.textBody,
      secondaryContainer: v.surfacePrimary,
      onSecondaryContainer: v.textBody,
      tertiary: cssHsl(0, 0, 26),
      onTertiary: accentFg,
      error: v.psWarning,
      onError: onPrimaryLight,
      surface: v.surfaceSecondary,
      onSurface: v.textBody,
      onSurfaceVariant: v.textSecondary,
      outline: v.borderDefault,
      outlineVariant: v.borderInput,
      shadow: cssHsl(0, 0, 0, 0.35),
      scrim: cssHsl(0, 0, 0, 0.55),
      inverseSurface: cssHsl(0, 0, 96),
      onInverseSurface: v.surfacePrimary,
      inversePrimary: v.psBlue,
      surfaceContainerHighest: v.surfacePrimary,
      surfaceContainerHigh: v.surfacePrimary,
      surfaceContainer: v.surfaceDivider,
      surfaceContainerLow: v.surfaceSecondary,
      surfaceContainerLowest: v.surfaceSecondary,
      surfaceTint: Colors.transparent,
    );
  }

  static TextTheme _textTheme(ColorScheme cs, VertisignageColors v) {
    final seed = ThemeData(colorScheme: cs, useMaterial3: true).textTheme;
    final base = GoogleFonts.interTextTheme(seed);

    TextStyle? display(TextStyle? s) => s?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: _emLetterSpacing(s.fontSize),
          color: v.textDisplay,
        );

    TextStyle? headline(TextStyle? s) => s?.copyWith(
          fontWeight: FontWeight.w300,
          letterSpacing: _emLetterSpacing(s.fontSize),
          color: v.textDisplay,
        );

    TextStyle? title(TextStyle? s) => s?.copyWith(
          fontWeight: FontWeight.w500,
          color: v.textDisplay,
        );

    TextStyle? body(TextStyle? s) => s?.copyWith(
          fontWeight: FontWeight.w400,
          color: cs.onSurface,
        );

    TextStyle? label(TextStyle? s) => s?.copyWith(
          fontWeight: FontWeight.w500,
          color: v.textSecondary,
        );

    return base.copyWith(
      displayLarge: display(base.displayLarge),
      displayMedium: display(base.displayMedium),
      displaySmall: display(base.displaySmall),
      headlineLarge: headline(base.headlineLarge),
      headlineMedium: headline(base.headlineMedium),
      headlineSmall: headline(base.headlineSmall),
      titleLarge: title(base.titleLarge),
      titleMedium: title(base.titleMedium),
      titleSmall: title(base.titleSmall),
      bodyLarge: body(base.bodyLarge),
      bodyMedium: body(base.bodyMedium),
      bodySmall: body(base.bodySmall)?.copyWith(color: cs.onSurfaceVariant),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: label(base.labelSmall)?.copyWith(
            fontSize: 12,
            height: 1.35,
          ),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required VertisignageColors tokens,
  }) {
    final colorScheme = _colorScheme(brightness, tokens);
    final textTheme = _textTheme(colorScheme, tokens);

    final borderRadiusMd = BorderRadius.circular(AppSpacing.radiusMd);
    final borderRadiusLg = BorderRadius.circular(AppSpacing.radiusLg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.surfaceSecondary,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: tokens.surfaceSecondary,
        foregroundColor: tokens.textBody,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 24),
      dividerTheme: DividerThemeData(color: tokens.borderDefault, thickness: 1),
      cardTheme: CardThemeData(
        color: tokens.surfacePrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusLg,
          side: BorderSide(color: tokens.borderDefault.withValues(alpha: 0.65)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfacePrimary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadiusLg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfacePrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        border: OutlineInputBorder(borderRadius: borderRadiusMd),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusMd,
          borderSide: BorderSide(color: tokens.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadiusMd,
          borderSide: BorderSide(color: tokens.ring, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadiusMd,
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s3,
          ),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusLg),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s3,
          ),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusLg),
          side: BorderSide(color: tokens.borderDefault),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          shape: RoundedRectangleBorder(borderRadius: borderRadiusLg),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }
}
