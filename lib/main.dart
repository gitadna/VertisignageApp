import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.init();
  runApp(const VertisignageApp());
}
