import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class AutoStartService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      String appPath = Platform.resolvedExecutable;

      if (kDebugMode || appPath.contains('flutter_tools')) {
        debugPrint('AutoStart: Skipping initialization in debug mode');
        return;
      }

      final exeFile = File(appPath);
      if (!await exeFile.exists()) {
        debugPrint('AutoStart: Executable not found at $appPath');
        return;
      }

      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: appPath,
        args: ['--autostart'],
      );

      _isInitialized = true;
      debugPrint('AutoStart: Initialized successfully');
    } catch (e, s) {
      debugPrint('AutoStart: Initialization failed: $e\n$s');
    }
  }

  static Future<bool> isEnabled() async {
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('AutoStart: Failed to check status: $e');
      return false;
    }
  }

  static Future<void> enable() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      await launchAtStartup.enable();
      debugPrint('AutoStart: Enabled');
    } catch (e, s) {
      debugPrint('AutoStart: Failed to enable: $e\n$s');
      throw Exception('Не удалось включить автозапуск: $e');
    }
  }

  static Future<void> disable() async {
    try {
      await launchAtStartup.disable();
      debugPrint('AutoStart: Disabled');
    } catch (e, s) {
      debugPrint('AutoStart: Failed to disable: $e\n$s');
      throw Exception('Не удалось отключить автозапуск: $e');
    }
  }

  static Future<void> toggle(bool enable) async {
    if (enable) {
      await AutoStartService.enable();
    } else {
      await AutoStartService.disable();
    }
  }
}