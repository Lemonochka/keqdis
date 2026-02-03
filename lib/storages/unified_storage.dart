import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

class PortableStorage {
  static String? _portableDir;

  static bool _isValidFilename(String filename) {
    if (filename.contains('..') || filename.contains('/') || filename.contains('\\')) {
      return false;
    }
    if (path.isAbsolute(filename)) {
      return false;
    }
    if (filename.contains(':') || filename.contains('|') || filename.contains('<') || filename.contains('>')) {
      return false;
    }
    final validPattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    if (!validPattern.hasMatch(filename)) {
      return false;
    }
    if (filename.length > 255) {
      return false;
    }
    return true;
  }

  static Future<String> getPortableDirectory() async {
    if (_portableDir != null) return _portableDir!;
    final exePath = Platform.resolvedExecutable;
    final exeDir = path.dirname(exePath);
    final dataDir = path.join(exeDir, 'data');
    final dir = Directory(dataDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _portableDir = dataDir;
    return dataDir;
  }

  /// Получить путь к файлу в портативной директории (с валидацией)
  static Future<String> getFilePath(String filename) async {
    if (!_isValidFilename(filename)) {
      throw ArgumentError('Недопустимое имя файла: $filename');
    }
    final dir = await getPortableDirectory();
    final filePath = path.join(dir, filename);
    final canonicalDataDir = path.canonicalize(dir);
    final canonicalFilePath = path.canonicalize(filePath);
    if (!canonicalFilePath.startsWith(canonicalDataDir)) {
      throw SecurityException('Path traversal attempt detected: $filename');
    }
    return filePath;
  }
}

/// Тип элемента в списке серверов
enum ServerItemType {
  manual,
  subscription
}

/// ОПТИМИЗИРОВАНО: Упрощенный элемент сервера
class ServerItem {
  final String id;
  final String config;
  final ServerItemType type;
  final String? subscriptionId;
  final String? subscriptionName;
  final DateTime addedAt;
  final bool isFavorite;

  // ОПТИМИЗАЦИЯ: Ленивая инициализация тяжелых вычислений
  String? _cachedDisplayName;
  String? _cachedCountryCode;

  ServerItem({
    required this.id,
    required this.config,
    required this.type,
    this.subscriptionId,
    this.subscriptionName,
    DateTime? addedAt,
    this.isFavorite = false,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'config': config,
    'type': type.name,
    'subscriptionId': subscriptionId,
    'subscriptionName': subscriptionName,
    'addedAt': addedAt.toIso8601String(),
    'isFavorite': isFavorite,
  };

  factory ServerItem.fromJson(Map<String, dynamic> json) {
    return ServerItem(
      id: json['id'] as String,
      config: json['config'] as String,
      type: ServerItemType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => ServerItemType.manual,
      ),
      subscriptionId: json['subscriptionId'] as String?,
      subscriptionName: json['subscriptionName'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  ServerItem copyWith({
    String? id,
    String? config,
    ServerItemType? type,
    String? subscriptionId,
    String? subscriptionName,
    DateTime? addedAt,
    bool? isFavorite,
  }) {
    return ServerItem(
      id: id ?? this.id,
      config: config ?? this.config,
      type: type ?? this.type,
      subscriptionId: subscriptionId ?? this.subscriptionId,
      subscriptionName: subscriptionName ?? this.subscriptionName,
      addedAt: addedAt ?? this.addedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// ОПТИМИЗАЦИЯ: Кэшированное получение кода страны
  String? get countryCode {
    if (_cachedCountryCode != null) return _cachedCountryCode;

    try {
      final name = displayName;

      // Упрощенные паттерны
      final patterns = [
        RegExp(r'\[([A-Z]{2})\]'),
        RegExp(r'\(([A-Z]{2})\)'),
        RegExp(r'\b([A-Z]{2})\s'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(name);
        if (match != null) {
          final code = match.group(1);
          if (code != null && _isValidCountryCode(code)) {
            _cachedCountryCode = code.toUpperCase();
            return _cachedCountryCode;
          }
        }
      }

      // Упрощенная карта стран
      final countryNames = {
        'finland': 'FI', 'estonia': 'EE', 'usa': 'US', 'russia': 'RU',
        'germany': 'DE', 'uk': 'GB', 'japan': 'JP', 'china': 'CN',
      };

      final lowerName = name.toLowerCase();
      for (final entry in countryNames.entries) {
        if (lowerName.contains(entry.key)) {
          _cachedCountryCode = entry.value;
          return _cachedCountryCode;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  bool _isValidCountryCode(String code) {
    const validCodes = {
      'FI', 'EE', 'US', 'RU', 'DE', 'GB', 'JP', 'CN', 'KR', 'NL',
      'SE', 'NO', 'DK', 'PL', 'ES', 'IT', 'FR', 'CA', 'AU',
    };
    return validCodes.contains(code.toUpperCase());
  }

  /// ОПТИМИЗАЦИЯ: Кэшированное отображаемое имя
  String get displayName {
    if (_cachedDisplayName != null) return _cachedDisplayName!;

    try {
      final uri = Uri.parse(config);
      if (uri.fragment.isNotEmpty) {
        _cachedDisplayName = Uri.decodeComponent(uri.fragment);
        return _cachedDisplayName!;
      }
      _cachedDisplayName = uri.host;
      return _cachedDisplayName!;
    } catch (e) {
      _cachedDisplayName = 'Unknown Server';
      return _cachedDisplayName!;
    }
  }

  /// Название без кода страны и emoji-флагов
  String get cleanDisplayName {
    var name = displayName;
    name = name.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true), '');
    name = name.replaceAll(RegExp(r'\[[A-Z]{2}\]'), '');
    name = name.replaceAll(RegExp(r'\([A-Z]{2}\)'), '');
    name = name.replaceAll(RegExp(r'\|[A-Z]{2}\|'), '');
    return name.trim();
  }
}

/// Подписка
class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime lastUpdated;
  final bool autoUpdate;
  final int serverCount;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.lastUpdated,
    this.autoUpdate = true,
    this.serverCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'lastUpdated': lastUpdated.toIso8601String(),
    'autoUpdate': autoUpdate,
    'serverCount': serverCount,
  };

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      autoUpdate: json['autoUpdate'] as bool? ?? true,
      serverCount: json['serverCount'] as int? ?? 0,
    );
  }

  Subscription copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? lastUpdated,
    bool? autoUpdate,
    int? serverCount,
  }) {
    return Subscription(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      serverCount: serverCount ?? this.serverCount,
    );
  }
}

/// ОПТИМИЗИРОВАНО: Унифицированное хранилище с минимальным кэшированием
class UnifiedStorage {
  static const String _serversFile = 'servers.json';
  static const String _subscriptionsFile = 'subscriptions.json';
  static const String _lastServerFile = 'last_server.txt';

  // ОПТИМИЗАЦИЯ: Убрали избыточное кэширование - данные загружаются только при необходимости

  /// Загрузить серверы (без кэша)
  static Future<List<ServerItem>> loadServers() async {
    try {
      final filePath = await PortableStorage.getFilePath(_serversFile);
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      return jsonList.map((json) => ServerItem.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Сохранить серверы
  static Future<void> saveServers(List<ServerItem> servers) async {
    try {
      final filePath = await PortableStorage.getFilePath(_serversFile);
      final file = File(filePath);
      final jsonList = servers.map((s) => s.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      throw Exception('Не удалось сохранить серверы');
    }
  }

  static Future<ServerItem> addManualServer(String config) async {
    final servers = await loadServers();
    if (servers.any((s) => s.config == config)) {
      throw Exception('Этот сервер уже добавлен');
    }
    final item = ServerItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      config: config,
      type: ServerItemType.manual,
    );
    servers.add(item);
    await saveServers(servers);
    return item;
  }

  static Future<void> deleteServer(String id) async {
    final servers = await loadServers();
    servers.removeWhere((s) => s.id == id);
    await saveServers(servers);
  }

  static Future<void> toggleFavorite(String serverId) async {
    final servers = await loadServers();
    final index = servers.indexWhere((s) => s.id == serverId);
    if (index == -1) {
      throw Exception('Сервер не найден');
    }
    servers[index] = servers[index].copyWith(
      isFavorite: !servers[index].isFavorite,
    );
    await saveServers(servers);
  }

  static Future<List<ServerItem>> getManualServers() async {
    final servers = await loadServers();
    return servers.where((s) => s.type == ServerItemType.manual).toList();
  }

  static Future<List<ServerItem>> getSubscriptionServers(String subscriptionId) async {
    final servers = await loadServers();
    return servers.where((s) =>
    s.type == ServerItemType.subscription &&
        s.subscriptionId == subscriptionId
    ).toList();
  }

  static Future<List<ServerItem>> getFavoriteServers() async {
    final servers = await loadServers();
    return servers.where((s) => s.isFavorite).toList();
  }

  static Future<void> saveLastServer(String serverId) async {
    try {
      final filePath = await PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);
      await file.writeAsString(serverId);
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  static Future<String?> loadLastServer() async {
    try {
      final filePath = await PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  static Future<ServerItem?> getLastServer() async {
    try {
      final lastId = await loadLastServer();
      if (lastId == null) return null;
      final servers = await loadServers();
      return servers.cast<ServerItem?>().firstWhere(
            (s) => s?.id == lastId,
        orElse: () => null,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<List<Subscription>> loadSubscriptions() async {
    try {
      final filePath = await PortableStorage.getFilePath(_subscriptionsFile);
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      return jsonList.map((json) => Subscription.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    try {
      final filePath = await PortableStorage.getFilePath(_subscriptionsFile);
      final file = File(filePath);
      final jsonList = subscriptions.map((sub) => sub.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      throw Exception('Не удалось сохранить подписки');
    }
  }

  static Future<Subscription> addSubscription({
    required String name,
    required String url,
    bool autoUpdate = true,
  }) async {
    final subscriptions = await loadSubscriptions();
    if (subscriptions.any((sub) => sub.url == url)) {
      throw Exception('Подписка с таким URL уже существует');
    }
    final subscription = Subscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      url: url,
      lastUpdated: DateTime.now(),
      autoUpdate: autoUpdate,
    );
    subscriptions.add(subscription);
    await saveSubscriptions(subscriptions);
    return subscription;
  }

  static Future<void> deleteSubscription(String subscriptionId) async {
    final subscriptions = await loadSubscriptions();
    subscriptions.removeWhere((sub) => sub.id == subscriptionId);
    await saveSubscriptions(subscriptions);
    final servers = await loadServers();
    servers.removeWhere((s) =>
    s.type == ServerItemType.subscription &&
        s.subscriptionId == subscriptionId
    );
    await saveServers(servers);
  }

  static Future<Subscription> updateSubscription(Subscription subscription) async {
    final subscriptions = await loadSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub.id == subscription.id);
    if (index == -1) {
      throw Exception('Подписка не найдена');
    }
    subscriptions[index] = subscription;
    await saveSubscriptions(subscriptions);
    return subscription;
  }

  static Future<void> updateSubscriptionServers({
    required String subscriptionId,
    required String subscriptionName,
    required List<String> newConfigs,
  }) async {
    final servers = await loadServers();
    servers.removeWhere((s) =>
    s.type == ServerItemType.subscription &&
        s.subscriptionId == subscriptionId
    );
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    for (final config in newConfigs) {
      servers.add(ServerItem(
        id: '${timestamp++}',
        config: config,
        type: ServerItemType.subscription,
        subscriptionId: subscriptionId,
        subscriptionName: subscriptionName,
      ));
    }
    await saveServers(servers);
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}