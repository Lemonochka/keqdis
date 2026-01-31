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
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      localPort: json['localPort'] ?? 2080,
      directDomains: json['directDomains'] ?? 'ru, yandex.ru, vk.com',
      blockedDomains: json['blockedDomains'] ?? '',
      directIps: json['directIps'] ?? '192.168.0.0/16, 10.0.0.0/8, 127.0.0.0/8',
      proxyDomains: json['proxyDomains'] ?? '',
      autoStart: json['autoStart'] ?? false,
      minimizeToTray: json['minimizeToTray'] ?? true,
      startMinimized: json['startMinimized'] ?? false,
      pingType: json['pingType'] ?? 'tcp',
      autoConnectLastServer: json['autoConnectLastServer'] ?? false,
    );
  }
}

class SettingsStorage {
  static const String _settingsFile = 'settings.json';

  /// Загрузить настройки из портативного хранилища
  static Future<AppSettings> loadSettings() async {
    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      if (!await file.exists()) {
        print('Файл настроек не найден, используем настройки по умолчанию');
        return AppSettings();
      }

      final content = await file.readAsString();
      final decoded = Map<String, dynamic>.from(json.decode(content));

      print('Настройки загружены из: $filePath');
      return AppSettings.fromJson(decoded);
    } catch (e) {
      print('Ошибка загрузки настроек: $e');
      return AppSettings();
    }
  }

  /// Сохранить настройки в портативное хранилище
  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final filePath = await PortableStorage.getFilePath(_settingsFile);
      final file = File(filePath);

      final jsonString = json.encode(settings.toJson());
      await file.writeAsString(jsonString);

      print('Настройки сохранены в: $filePath');
    } catch (e) {
      print('Ошибка сохранения настроек: $e');
      throw Exception('Не удалось сохранить настройки');
    }
  }

  /// Сбросить настройки на дефолтные
  static Future<void> resetSettings() async {
    await saveSettings(AppSettings());
    print('Настройки сброшены на значения по умолчанию');
  }

  /// Экспорт настроек в JSON строку
  static Future<String> exportSettings() async {
    final settings = await loadSettings();
    return json.encode(settings.toJson());
  }

  /// Импорт настроек из JSON строки
  static Future<void> importSettings(String jsonString) async {
    try {
      final decoded = Map<String, dynamic>.from(json.decode(jsonString));
      final settings = AppSettings.fromJson(decoded);
      await saveSettings(settings);
      print('Настройки импортированы успешно');
    } catch (e) {
      print('Ошибка импорта настроек: $e');
      throw Exception('Некорректный формат настроек');
    }
  }
}