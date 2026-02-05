import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'storages/improved_settings_storage.dart';
import 'services/autostart_service.dart';
import 'screens/improved_theme_manager.dart';
import 'utils/single_instance_manager.dart';
import 'screens/UI/pages/home_screen_optimized.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isAlreadyRunning = await SingleInstanceManager.isAlreadyRunning();
  if (isAlreadyRunning) {
    try {
      if (Platform.isWindows) {
        await Process.run('powershell', [
          '-Command',
          '''
          \$wshell = New-Object -ComObject wscript.shell;
          \$wshell.AppActivate("KEQDIS")
          '''
        ]);
      }
    } catch (e) {
      // Failed to activate window
    }

    exit(0);
///    return;
  }

  try {
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe']);
  } catch (e) {
    // No hung processes
  }

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1400, 850),
    minimumSize: Size(1000, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'KEQDIS',
  );

  bool isAutoStarted = false;

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await AutoStartService.initialize();
    final settings = await SettingsStorage.loadSettings();

    final args = Platform.executableArguments;
    isAutoStarted = args.contains('--autostart') || args.contains('--minimized');

    await windowManager.show();

    if ((isAutoStarted && settings.startMinimized) ||
        (!isAutoStarted && settings.startMinimized && settings.minimizeToTray)) {
      await Future.delayed(const Duration(milliseconds: 500));
      await windowManager.hide();
    } else {
      await windowManager.focus();
    }
  });

  await ThemeManager().loadTheme();

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
          theme: ThemeManager().getThemeData(),
          debugShowCheckedModeBanner: false,
          home: HomeScreen(isAutoStarted: isAutoStarted),
        );
      },
    );
  }
}