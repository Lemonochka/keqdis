import 'dart:convert';
import 'dart:io';
import 'unified_storage.dart';

class AppSettings {
  int localPort;
  String directDomains;
  String blockedDomains;
  String directIps;
  String proxyDomains;
  bool autoStart;
  bool minimizeToTray;
  bool startMinimized;
  String pingType;
  bool autoConnectLastServer;
  String lastVpnMode;

  AppSettings({
    this.localPort = 2080,
    this.directDomains = 'ru, yandex.ru, vk.com',
    this.blockedDomains = '',
    this.directIps = '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
    this.proxyDomains = '',
    this.autoStart = false,
    this.minimizeToTray = true,
    this.startMinimized = false,
    this.pingType = 'tcp',
    this.autoConnectLastServer = false,
    this.lastVpnMode = 'systemProxy',
  });

  Map<String, dynamic> toJson() => {
    'localPort': localPort,
    'directDomains': directDomains,
    'blockedDomains': blockedDomains,
    'directIps': directIps,
    'proxyDomains': proxyDomains,
    'autoStart': autoStart,
    'minimizeToTray': minimizeToTray,
    'startMinimized': startMinimized,
    'pingType': pingType,
    'autoConnectLastServer': autoConnectLastServer,
    'lastVpnMode': lastVpnMode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      localPort: json['localPort'] ?? 2080,
      directDomains: json['directDomains'] ?? 'yandex.ru, vk.com',
      blockedDomains: json['blockedDomains'] ?? '',
      directIps: json['directIps'] ?? '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
      proxyDomains: json['proxyDomains'] ?? '',
      autoStart: json['autoStart'] ?? false,
      minimizeToTray: json['minimizeToTray'] ?? true,
      startMinimized: json['startMinimized'] ?? false,
      pingType: json['pingType'] ?? 'tcp',
      autoConnectLastServer: json['autoConnectLastServer'] ?? false,
      lastVpnMode: json['lastVpnMode'] ?? 'systemProxy',
    );
  }
}

class SettingsStorage {
  static const String _settingsFile = 'settings.json';

  static Future<AppSettings> loadSettings() async {
    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      if (!await file.exists()) {
        return AppSettings();
      }

      final content = await file.readAsString();
      final decoded = Map<String, dynamic>.from(json.decode(content));

      return AppSettings.fromJson(decoded);
    } catch (e) {
      return AppSettings();
    }
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      final jsonString = json.encode(settings.toJson());
      await file.writeAsString(jsonString);
    } catch (e) {
      throw Exception('Не удалось сохранить настройки');
    }
  }

  static Future<void> resetSettings() async {
    await saveSettings(AppSettings());
  }

  static Future<String> exportSettings() async {
    final settings = await loadSettings();
    return json.encode(settings.toJson());
  }

  static Future<void> importSettings(String jsonString) async {
    try {
      final decoded = Map<String, dynamic>.from(json.decode(jsonString));
      final settings = AppSettings.fromJson(decoded);
      await saveSettings(settings);
    } catch (e) {
      throw Exception('Некорректный формат настроек');
    }
  }
}