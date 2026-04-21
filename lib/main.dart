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
import 'localization/app_localization.dart';
import 'services/debug_log_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  DebugLogService().installDebugPrintHook();

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
  await AppLocalization().load();

  final launchArgs = <String>{
    ...args,
    ...Platform.executableArguments,
  };
  final isAutoStarted =
      launchArgs.contains('--autostart') || launchArgs.contains('--minimized');
  final isElevated = launchArgs.contains('--elevated');

  // При автозапуске используем настройку или флаг аргумента
  final shouldStartMinimized = settings.startMinimized || isAutoStarted;

  debugPrint('App started with args: ${launchArgs.toList()}');
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

  await windowManager.setPreventClose(true);

  // Always wait for the window to be ready, otherwise on Windows the window
  // can briefly appear even when we intend to start minimized.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (shouldStartMinimized) {
      debugPrint('Starting minimized to tray');
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
      return;
    }
    await windowManager.show();
    await windowManager.focus();
    debugPrint('Window shown');
  });

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
    // Процесс не был запущен — ОК
  }

  try {
    await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe'], runInShell: false);
    debugPrint('Killed legacy sing-box.exe');
  } catch (e) {
    // Процесс не был запущен — ОК
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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver, WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    debugPrint('App lifecycle observer registered');
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('App lifecycle observer removed');
    super.dispose();
  }

  @override
  void onWindowClose() async {
    debugPrint('Window close requested, running cleanup...');
    await _cleanupOnExit();
    await windowManager.destroy();
  }

  @override
  Future<bool> didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('App lifecycle state changed: $state');
    return false;
  }

  Future<void> _cleanupOnExit() async {
    try {
      debugPrint('Cleanup: Stopping VPN processes...');

      if (Platform.isWindows) {
        await Future.wait([
          _killProcess('xray.exe'),
          _killProcess('sing-box.exe'),
        ]);
      }

      debugPrint('Cleanup: Clearing system proxy...');
      await SystemProxy.clearProxy().timeout(const Duration(seconds: 2));
      debugPrint('Cleanup: System proxy cleared');

      debugPrint('Cleanup: Releasing instance lock...');
      await SingleInstanceManager.release();
      debugPrint('Cleanup: Instance lock released');

      debugPrint('Cleanup completed successfully');
    } catch (e, s) {
      debugPrint('Cleanup error: $e\n$s');
    }
  }

  Future<void> _killProcess(String exeName) async {
    try {
      final result = await Process.run(
        'taskkill',
        ['/F', '/IM', exeName],
        runInShell: false,
      ).timeout(const Duration(seconds: 2));
      debugPrint('Cleanup: $exeName killed (exit code: ${result.exitCode})');
    } catch (e) {
      debugPrint('Cleanup: $exeName not running or failed to kill: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ThemeManager(), AppLocalization()]),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeManager().getThemeData(),
          locale: AppLocalization().locale,
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