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

  // FIX: Перехватываем закрытие окна для гарантированной очистки
  await windowManager.setPreventClose(true);

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

// FIX: Добавлен WindowListener для надёжного перехвата закрытия на Windows
class _MyAppState extends State<MyApp> with WidgetsBindingObserver, WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // FIX: Подписываемся на события окна
    windowManager.addListener(this);
    debugPrint('App lifecycle observer registered');
  }

  @override
  void dispose() {
    // FIX: Отписываемся от событий окна
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('App lifecycle observer removed');
    super.dispose();
  }

  // FIX: Используем onWindowClose вместо ненадёжного didChangeAppLifecycleState
  @override
  void onWindowClose() async {
    debugPrint('Window close requested, running cleanup...');
    await _cleanupOnExit();
    await windowManager.destroy();
  }

  @override
  Future<bool> didChangeAppLifecycleState(AppLifecycleState state) async {
    debugPrint('App lifecycle state changed: $state');
    // FIX: Убрали обработку detached — теперь очистка через onWindowClose
    return false;
  }

  Future<void> _cleanupOnExit() async {
    try {
      debugPrint('Cleanup: Stopping VPN processes...');

      if (Platform.isWindows) {
        // FIX: Запускаем kill процессов параллельно для ускорения
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

  // FIX: Вынесенный метод для убийства процесса
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
