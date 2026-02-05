import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'unified_storage.dart';

class AppSettings {
  final int localPort;
  final String directDomains;
  final String blockedDomains;
  final String directIps;
  final String proxyDomains;
  final bool autoStart;
  final bool minimizeToTray;
  final bool startMinimized;
  final String pingType;
  final bool autoConnectLastServer;
  final String lastVpnMode;

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
      localPort: json['localPort'] is int ? json['localPort'] : 2080,
      directDomains: json['directDomains'] is String
          ? json['directDomains']
          : 'yandex.ru, vk.com',
      blockedDomains:
          json['blockedDomains'] is String ? json['blockedDomains'] : '',
      directIps: json['directIps'] is String
          ? json['directIps']
          : '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
      proxyDomains: json['proxyDomains'] is String ? json['proxyDomains'] : '',
      autoStart: json['autoStart'] is bool ? json['autoStart'] : false,
      minimizeToTray:
          json['minimizeToTray'] is bool ? json['minimizeToTray'] : true,
      startMinimized:
          json['startMinimized'] is bool ? json['startMinimized'] : false,
      pingType: json['pingType'] is String ? json['pingType'] : 'tcp',
      autoConnectLastServer: json['autoConnectLastServer'] is bool
          ? json['autoConnectLastServer']
          : false,
      lastVpnMode:
          json['lastVpnMode'] is String ? json['lastVpnMode'] : 'systemProxy',
    );
  }
}

class SettingsStorage {
  static const String _settingsFile = 'settings.json';
  static AppSettings? _cachedSettings;

  static Future<AppSettings> loadSettings() async {
    if (_cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = Map<String, dynamic>.from(json.decode(content));
          _cachedSettings = AppSettings.fromJson(decoded);
          return _cachedSettings!;
        }
      }
    } catch (e, s) {
      debugPrint('Failed to load settings: $e\n$s');
    }
    
    _cachedSettings = AppSettings();
    return _cachedSettings!;
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      final jsonString = json.encode(settings.toJson());
      await file.writeAsString(jsonString);
      _cachedSettings = settings;
    } catch (e, s) {
      debugPrint('Failed to save settings: $e\n$s');
      throw Exception('Не удалось сохранить настройки');
    }
  }

  static Future<void> resetSettings() async {
    final defaultSettings = AppSettings();
    await saveSettings(defaultSettings);
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
