import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';

/// Single-route kiosk shell — no navigation or business logic.
class KioskPlaceholderScreen extends StatelessWidget {
  const KioskPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          AppConstants.appName,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
