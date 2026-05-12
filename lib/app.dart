import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/kiosk_shell/presentation/app_shell.dart';
import 'features/kiosk_shell/presentation/boot_splash.dart';

class VertisignageApp extends StatelessWidget {
  const VertisignageApp({super.key, required this.deferredInit});

  /// Heavy bootstrap kicked off after the first frame by [BootSplash]. Must be idempotent so
  /// the splash can retry safely on hot-reload or recovery rebuilds.
  final Future<void> Function() deferredInit;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: BootSplash(
        deferredInit: deferredInit,
        child: const AppShell(),
      ),
    );
  }
}
