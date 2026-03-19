import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/core/system_proxy.dart';
import 'package:window_manager/window_manager.dart';
import 'storages/improved_settings_storage.dart';
import 'screens/improved_theme_manager.dart';
import 'utils/single_instance_manager.dart';
import 'screens/UI/pages/home_screen_optimized.dart';
import 'screens/UI/widgets/custom_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await UnifiedStorage.init();

  final isAlreadyRunning = await SingleInstanceManager.isAlreadyRunning();
  if (isAlreadyRunning) {
    debugPrint('Another instance is already running. Exiting...');
    exit(0);
  }

  await _killLegacyProcesses();

  await windowManager.ensureInitialized();

  final settings = await SettingsStorage.loadSettings();
  await ThemeManager().loadTheme();

  final args = Platform.executableArguments;
  final isAutoStarted = args.contains('--autostart') || args.contains('--minimized');
  final isElevated = args.contains('--elevated');

  final shouldStartMinimized = settings.startMinimized;

  debugPrint('App started with args: $args');
  debugPrint('Auto-started: $isAutoStarted, Elevated: $isElevated, StartMinimized: $shouldStartMinimized');

  WindowOptions windowOptions = WindowOptions(
    size: const Size(1400, 850),
    minimumSize: const Size(1000, 650),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: shouldStartMinimized,
    titleBarStyle: TitleBarStyle.normal,
    title: 'KEQDIS',
  );

  await windowManager.setSize(windowOptions.size!);
  await windowManager.setMinimumSize(windowOptions.minimumSize!);
  await windowManager.center();

  if (!shouldStartMinimized) {
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      debugPrint('Window shown');
    });
  } else {
    debugPrint('Starting minimized to tray');
  }

  runApp(MyApp(
    isAutoStarted: isAutoStarted,
    startMinimized: shouldStartMinimized,
  ));
}

Future<void> _killLegacyProcesses() async {
  if (!Platform.isWindows) return;

  try {
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe'], runInShell: false);
    debugPrint('Killed legacy xray.exe');
  } catch (e) {
  }

  try {
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    debugPrint('Killed legacy sing-box.exe');
  } catch (e) {
  }
}

class MyApp extends StatefulWidget {
  final bool isAutoStarted;
  final bool startMinimized;

  const MyApp({
    super.key,
    required this.isAutoStarted,
    this.startMinimized = false,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('App lifecycle observer registered');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('App lifecycle observer removed');
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('App lifecycle state changed: $state');

    if (state == AppLifecycleState.detached) {
      debugPrint('App is closing, running cleanup...');
      await _cleanupOnExit();
    }
  }

  Future<void> _cleanupOnExit() async {
    try {
      debugPrint('Cleanup: Stopping VPN processes...');

      if (Platform.isWindows) {
        try {
          final xrayResult = await Process.run(
            'taskkill',
            ['/F', '/IM', 'xray.exe'],
            runInShell: false,
          ).timeout(const Duration(seconds: 2));
          debugPrint('Cleanup: xray.exe killed (exit code: ${xrayResult.exitCode})');
        } catch (e) {
          debugPrint('Cleanup: xray.exe not running or failed to kill: $e');
        }

        try {
          final singboxResult = await Process.run(
            'taskkill',
            ['/F', '/IM', 'sing-box.exe'],
            runInShell: false,
          ).timeout(const Duration(seconds: 2));
          debugPrint('Cleanup: sing-box.exe killed (exit code: ${singboxResult.exitCode})');
        } catch (e) {
          debugPrint('Cleanup: sing-box.exe not running or failed to kill: $e');
        }
      }

      debugPrint('Cleanup: Clearing system proxy...');
      await SystemProxy.clearProxy().timeout(const Duration(seconds: 2));
      debugPrint('Cleanup: System proxy cleared');

      // Освобождаем lock файл
      debugPrint('Cleanup: Releasing instance lock...');
      await SingleInstanceManager.release();
      debugPrint('Cleanup: Instance lock released');

      debugPrint('Cleanup completed successfully');
    } catch (e, s) {
      debugPrint('Cleanup error: $e\n$s');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager(),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeManager().getThemeData(),
          debugShowCheckedModeBanner: false,
          home: HomeScreen(
            isAutoStarted: widget.isAutoStarted,
            startMinimized: widget.startMinimized,
          ),
        );
      },
    );
  }
}