import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoStartService {
  static Future<void> initialize() async {
    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  static Future<bool> isEnabled() async {
    return await launchAtStartup.isEnabled();
  }

  static Future<void> enable() async {
    await launchAtStartup.enable();
  }

  static Future<void> disable() async {
    await launchAtStartup.disable();
  }

  static Future<void> toggle(bool enable) async {
    if (enable) {
      await AutoStartService.enable();
    } else {
      await AutoStartService.disable();
    }
  }
}