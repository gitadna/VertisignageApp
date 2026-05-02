import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'features/kiosk_shell/presentation/app_shell.dart';

class VertisignageApp extends StatelessWidget {
  const VertisignageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
