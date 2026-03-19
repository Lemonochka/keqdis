import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'unified_storage.dart';

/// Режим маршрутизации приложений в TUN-режиме
enum AppRoutingMode {
  allProxy,

  onlySelected,

  allExceptSelected,
}

extension AppRoutingModeLabel on AppRoutingMode {
  String get label {
    switch (this) {
      case AppRoutingMode.allProxy:
        return 'Всё через VPN';
      case AppRoutingMode.onlySelected:
        return 'Только выбранные';
      case AppRoutingMode.allExceptSelected:
        return 'Всё кроме выбранных';
    }
  }
}

class AppRoutingStorage {
  static const String _fileName = 'app_routing.json';
  static Set<String>? _cachedApps;
  static AppRoutingMode? _cachedMode;

  static Future<({Set<String> apps, AppRoutingMode mode})> load() async {
    if (_cachedApps != null && _cachedMode != null) {
      return (apps: Set<String>.from(_cachedApps!), mode: _cachedMode!);
    }

    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_fileName);
      final file = File(filePath);

      if (!await file.exists()) {
        _cachedApps = {};
        _cachedMode = AppRoutingMode.allProxy;
        return (apps: <String>{}, mode: AppRoutingMode.allProxy);
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _cachedApps = {};
        _cachedMode = AppRoutingMode.allProxy;
        return (apps: <String>{}, mode: AppRoutingMode.allProxy);
      }

      final Map<String, dynamic> json_ = json.decode(content);

      final List<dynamic> appsList = json_['apps'] as List<dynamic>? ?? [];
      final String modeStr = json_['mode'] as String? ?? 'allProxy';

      _cachedApps = appsList.map((e) => e.toString()).toSet(); // регистр сохраняем — sing-box регистрозависим
      _cachedMode = _modeFromString(modeStr);

      return (apps: Set<String>.from(_cachedApps!), mode: _cachedMode!);
    } catch (e) {
      debugPrint('AppRoutingStorage: load error: $e');
      _cachedApps = {};
      _cachedMode = AppRoutingMode.allProxy;
      return (apps: <String>{}, mode: AppRoutingMode.allProxy);
    }
  }

  static Future<void> save({
    required Set<String> apps,
    required AppRoutingMode mode,
  }) async {
    try {
      await PortableStorage.getPortableDirectory();
      final filePath = PortableStorage.getFilePath(_fileName);
      final file = File(filePath);

      final data = {
        'mode': _modeToString(mode),
        'apps': apps.toList()..sort(),
      };

      await file.writeAsString(json.encode(data));
      _cachedApps = Set.from(apps);
      _cachedMode = mode;
      debugPrint('AppRoutingStorage: saved ${apps.length} apps, mode=${mode.name}');
    } catch (e) {
      debugPrint('AppRoutingStorage: save error: $e');
      rethrow;
    }
  }

  static AppRoutingMode _modeFromString(String s) {
    switch (s) {
      case 'onlySelected':
        return AppRoutingMode.onlySelected;
      case 'allExceptSelected':
        return AppRoutingMode.allExceptSelected;
      default:
        return AppRoutingMode.allProxy;
    }
  }

  static String _modeToString(AppRoutingMode mode) {
    switch (mode) {
      case AppRoutingMode.onlySelected:
        return 'onlySelected';
      case AppRoutingMode.allExceptSelected:
        return 'allExceptSelected';
      case AppRoutingMode.allProxy:
        return 'allProxy';
    }
  }

  static void invalidateCache() {
    _cachedApps = null;
    _cachedMode = null;
  }

  static Future<Set<String>> loadVpnApps() async {
    final result = await load();
    return result.apps;
  }

  static Future<void> saveVpnApps(Set<String> apps) async {
    final current = await load();
    await save(apps: apps, mode: current.mode);
  }
}