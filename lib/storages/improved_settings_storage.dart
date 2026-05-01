import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'unified_storage.dart';
import '../utils/security_hardening.dart';

class AppSettings {
  final int localPort;
  final bool useCustomDns;
  final String customDnsServers;
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
  final String appLanguage;
  final bool debugMode;
  final bool shareDeviceHwid;
  final String deviceHwid;

  AppSettings({
    this.localPort = 2080,
    this.useCustomDns = false,
    this.customDnsServers = '1.1.1.1, 8.8.8.8',
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
    this.appLanguage = 'ru',
    this.debugMode = false,
    this.shareDeviceHwid = true,
    this.deviceHwid = '',
  });

  Map<String, dynamic> toJson() => {
    'localPort': localPort,
    'useCustomDns': useCustomDns,
    'customDnsServers': customDnsServers,
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
    'appLanguage': appLanguage,
    'debugMode': debugMode,
    'shareDeviceHwid': shareDeviceHwid,
    'deviceHwid': deviceHwid,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      localPort: json['localPort'] is int ? json['localPort'] : 2080,
      useCustomDns: json['useCustomDns'] is bool ? json['useCustomDns'] : false,
      customDnsServers: json['customDnsServers'] is String
          ? json['customDnsServers']
          : '1.1.1.1, 8.8.8.8',
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
      appLanguage: json['appLanguage'] is String ? json['appLanguage'] : 'ru',
      debugMode: json['debugMode'] is bool ? json['debugMode'] : false,
      shareDeviceHwid: json['shareDeviceHwid'] is bool
          ? json['shareDeviceHwid']
          : true,
      deviceHwid: json['deviceHwid'] is String ? json['deviceHwid'] : '',
    );
  }
}

class SettingsStorage {
  static const String _settingsFile = 'settings.json';
  static const String _serverGroupsStateFile = 'server_groups_state.json';
  static AppSettings? _cachedSettings;
  static Map<String, bool>? _cachedCollapsedServerGroups;

  static Future<AppSettings> loadSettings() async {
    if (_cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = Map<String, dynamic>.from(json.decode(content));
          final parsed = AppSettings.fromJson(decoded);
          final normalizedHwid = parsed.deviceHwid.trim();
          if (normalizedHwid.isEmpty) {
            final withHwid = AppSettings(
              localPort: parsed.localPort,
              useCustomDns: parsed.useCustomDns,
              customDnsServers: parsed.customDnsServers,
              directDomains: parsed.directDomains,
              blockedDomains: parsed.blockedDomains,
              directIps: parsed.directIps,
              proxyDomains: parsed.proxyDomains,
              autoStart: parsed.autoStart,
              minimizeToTray: parsed.minimizeToTray,
              startMinimized: parsed.startMinimized,
              pingType: parsed.pingType,
              autoConnectLastServer: parsed.autoConnectLastServer,
              lastVpnMode: parsed.lastVpnMode,
              appLanguage: parsed.appLanguage,
              debugMode: parsed.debugMode,
              shareDeviceHwid: parsed.shareDeviceHwid,
              deviceHwid: _generateHwid(),
            );
            _cachedSettings = withHwid;
            await saveSettings(withHwid);
            return _cachedSettings!;
          }
          _cachedSettings = parsed;
          return _cachedSettings!;
        }
      }
    } catch (e, s) {
      debugPrint('Failed to load settings: $e\n$s');
    }

    _cachedSettings = AppSettings(deviceHwid: _generateHwid());
    return _cachedSettings!;
  }

  static String _generateHwid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(0x7fffffff);
    final host = Platform.localHostname;
    final seed = '$host-$now-$random';
    return base64UrlEncode(utf8.encode(seed)).replaceAll('=', '');
  }

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_settingsFile);

      final jsonString = json.encode(settings.toJson());
      await SecurityHardening.writeStringAtomically(filePath, jsonString);
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

  static Future<Map<String, bool>> loadCollapsedServerGroups() async {
    if (_cachedCollapsedServerGroups != null) {
      return Map<String, bool>.from(_cachedCollapsedServerGroups!);
    }
    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_serverGroupsStateFile);
      final file = File(filePath);
      if (!await file.exists()) {
        _cachedCollapsedServerGroups = const <String, bool>{};
        return const <String, bool>{};
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cachedCollapsedServerGroups = const <String, bool>{};
        return const <String, bool>{};
      }
      final decoded = Map<String, dynamic>.from(json.decode(raw));
      final out = <String, bool>{};
      for (final e in decoded.entries) {
        if (e.value is bool) out[e.key] = e.value as bool;
      }
      _cachedCollapsedServerGroups = Map<String, bool>.from(out);
      return out;
    } catch (_) {
      _cachedCollapsedServerGroups = const <String, bool>{};
      return const <String, bool>{};
    }
  }

  static Future<void> saveCollapsedServerGroups(Map<String, bool> state) async {
    _cachedCollapsedServerGroups = Map<String, bool>.from(state);
    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_serverGroupsStateFile);
      await SecurityHardening.writeStringAtomically(
        filePath,
        json.encode(state),
      );
    } catch (_) {}
  }

  static Map<String, bool> getCachedCollapsedServerGroups() {
    if (_cachedCollapsedServerGroups == null) {
      return const <String, bool>{};
    }
    return Map<String, bool>.from(_cachedCollapsedServerGroups!);
  }
}