import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'storages/improved_settings_storage.dart';
import 'services/autostart_service.dart';
import 'screens/improved_theme_manager.dart';
import 'utils/single_instance_manager.dart';
import 'screens/UI/pages/home_screen_optimized.dart';
import 'screens/UI/widgets/custom_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage first, as it's crucial for other components.
  await UnifiedStorage.init();

  final isAlreadyRunning = await SingleInstanceManager.isAlreadyRunning();
  if (isAlreadyRunning) {
    // Logic to focus existing window can be added here.
    exit(0);
  }

  // Clean up any lingering core processes from previous sessions.
  try {
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe']);
  } catch (e) {
    // Ignore if no process is found.
  }

  await windowManager.ensureInitialized();

  final settings = await SettingsStorage.loadSettings();
  await ThemeManager().loadTheme(); // Removed argument

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1400, 850),
    minimumSize: Size(1000, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'KEQDIS',
  );

  final args = Platform.executableArguments;
  final isAutoStarted = args.contains('--autostart') || args.contains('--minimized');

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (isAutoStarted && settings.startMinimized) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(MyApp(isAutoStarted: isAutoStarted));
}

class MyApp extends StatelessWidget {
  final bool isAutoStarted;

  const MyApp({super.key, required this.isAutoStarted});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager(),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeManager().getThemeData(),
          debugShowCheckedModeBanner: false,
          home: HomeScreen(isAutoStarted: isAutoStarted),
        );
      },
    );
  }
}
