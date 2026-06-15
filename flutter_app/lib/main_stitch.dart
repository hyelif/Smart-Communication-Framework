import 'package:flutter/material.dart';

import 'core/dependency_injection.dart';
import 'stitch_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  runApp(const StitchApp());
}