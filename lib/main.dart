import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(StackSpaceApp(settings: settings));
}
