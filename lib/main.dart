import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'core_manager.dart';
import 'unified_storage.dart';
import 'improved_settings_storage.dart';
import 'system_proxy.dart';
import 'tray_service.dart';
import 'autostart_service.dart';
import 'improved_theme_manager.dart';
import 'improved_subscription_service.dart';
import 'single_instance_manager.dart';
import 'screens/main_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ========== ПРОВЕРКА SINGLE INSTANCE ==========
  final isAlreadyRunning = await SingleInstanceManager.isAlreadyRunning();
  if (isAlreadyRunning) {
    print('⚠️ Приложение уже запущено. Активируем существующее окно...');

    // ИСПРАВЛЕНО: Вместо показа диалога, пытаемся активировать существующее окно
    try {
      // Пытаемся найти и активировать окно через WinAPI (Windows)
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
      print('Не удалось активировать окно: $e');
    }

    // Закрываем текущий экземпляр без показа UI
    exit(0);
    return;
  }

  // Убиваем все зависшие процессы Xray при старте
  try {
    print('Проверка зависших процессов Xray...');
    await Process.run('taskkill', ['/F', '/IM', 'xray.exe']);
    print('Старые процессы Xray остановлены');
  } catch (e) {
    print('Нет зависших процессов Xray');
  }

  // Инициализация window manager
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

  // ========== ПРОВЕРКА АВТОЗАПУСКА ==========
  bool isAutoStarted = false;

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await AutoStartService.initialize();
    final settings = await SettingsStorage.loadSettings();

    // Проверяем, запущено ли приложение через автозапуск
    final args = Platform.executableArguments;
    isAutoStarted = args.contains('--autostart') || args.contains('--minimized');

    print('🔍 Режим запуска: ${isAutoStarted ? "АВТОЗАПУСК" : "ОБЫЧНЫЙ"}');
    print('🔍 startMinimized: ${settings.startMinimized}');

    // Всегда показываем окно сначала
    await windowManager.show();

    // Сворачиваем ТОЛЬКО если:
    // 1. Это автозапуск И включен startMinimized
    // 2. ИЛИ обычный запуск И включен startMinimized И minimizeToTray
    if ((isAutoStarted && settings.startMinimized) ||
        (!isAutoStarted && settings.startMinimized && settings.minimizeToTray)) {
      print('✅ Сворачивание в трей...');
      // Небольшая задержка для инициализации трея
      await Future.delayed(const Duration(milliseconds: 500));
      await windowManager.hide();
    } else {
      print('✅ Показываем окно');
      await windowManager.focus();
    }
  });

  // Загружаем тему
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
          home: MainShell(isAutoStarted: isAutoStarted),
        );
      },
    );
  }
}