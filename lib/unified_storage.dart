import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Портативное хранилище - все данные рядом с .exe
class PortableStorage {
  static String? _portableDir;

  /// БЕЗОПАСНОСТЬ: Валидация имени файла
  static bool _isValidFilename(String filename) {
    // Запрещаем path traversal
    if (filename.contains('..') || filename.contains('/') || filename.contains('\\')) {
      return false;
    }

    // Запрещаем абсолютные пути
    if (path.isAbsolute(filename)) {
      return false;
    }

    // Запрещаем специальные символы
    if (filename.contains(':') || filename.contains('|') || filename.contains('<') || filename.contains('>')) {
      return false;
    }

    // Разрешаем только буквы, цифры, точки, тире и подчеркивания
    final validPattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    if (!validPattern.hasMatch(filename)) {
      return false;
    }

    // Ограничиваем длину
    if (filename.length > 255) {
      return false;
    }

    return true;
  }

  /// Получить портативную директорию (рядом с .exe)
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

  /// ИСПРАВЛЕНО: Получить путь к файлу в портативной директории (с валидацией)
  static Future<String> getFilePath(String filename) async {
    // БЕЗОПАСНОСТЬ: Валидация имени файла
    if (!_isValidFilename(filename)) {
      throw ArgumentError('Недопустимое имя файла: $filename');
    }

    final dir = await getPortableDirectory();
    final filePath = path.join(dir, filename);

    // ДОПОЛНИТЕЛЬНАЯ ПРОВЕРКА: Убедиться, что путь внутри data директории
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

/// Элемент в едином списке серверов
class ServerItem {
  final String id;
  final String config;
  final ServerItemType type;
  final String? subscriptionId;
  final String? subscriptionName;
  final DateTime addedAt;
  final bool isFavorite;

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

  String? get countryCode {
    try {
      final name = displayName;

      final emojiPattern = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
      final emojiMatch = emojiPattern.firstMatch(name);
      if (emojiMatch != null) {
        final emoji = emojiMatch.group(0);
        final code = _flagEmojiToCountryCode(emoji ?? '');
        if (code != null) return code;
      }

      final patterns = [
        RegExp(r'\[([A-Z]{2})\]'),
        RegExp(r'\(([A-Z]{2})\)'),
        RegExp(r'\b([A-Z]{2})\s'),
        RegExp(r'\s([A-Z]{2})\b'),
        RegExp(r'^([A-Z]{2})\s'),
        RegExp(r'\|([A-Z]{2})\|'),
        RegExp(r'_([A-Z]{2})_'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(name);
        if (match != null) {
          final code = match.group(1);
          if (code != null && code.length == 2 && _isValidCountryCode(code)) {
            return code.toUpperCase();
          }
        }
      }

      final countryNames = {
        'finland': 'FI', 'финлянд': 'FI', 'suomi': 'FI',
        'estonia': 'EE', 'эстон': 'EE', 'eesti': 'EE',
        'usa': 'US', 'united states': 'US', 'америк': 'US',
        'russia': 'RU', 'росси': 'RU',
        'germany': 'DE', 'герман': 'DE', 'deutschland': 'DE',
        'uk': 'GB', 'britain': 'GB', 'британ': 'GB', 'united kingdom': 'GB',
        'japan': 'JP', 'япон': 'JP',
        'china': 'CN', 'кита': 'CN',
        'korea': 'KR', 'коре': 'KR',
        'netherlands': 'NL', 'holland': 'NL', 'нидерланд': 'NL',
        'sweden': 'SE', 'швец': 'SE', 'sverige': 'SE',
        'norway': 'NO', 'норвег': 'NO', 'norge': 'NO',
        'denmark': 'DK', 'дани': 'DK', 'danmark': 'DK',
        'poland': 'PL', 'польш': 'PL', 'polska': 'PL',
        'spain': 'ES', 'испан': 'ES', 'españa': 'ES',
        'italy': 'IT', 'итал': 'IT', 'italia': 'IT',
        'france': 'FR', 'франц': 'FR',
        'canada': 'CA', 'канад': 'CA',
        'australia': 'AU', 'австрал': 'AU',
        'turkey': 'TR', 'турц': 'TR', 'türkiye': 'TR',
        'ukraine': 'UA', 'украин': 'UA',
      };

      final lowerName = name.toLowerCase();
      for (final entry in countryNames.entries) {
        if (lowerName.contains(entry.key)) {
          return entry.value;
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
      'SE', 'NO', 'DK', 'PL', 'ES', 'IT', 'FR', 'CA', 'AU', 'BR',
      'IN', 'TR', 'UA', 'CH', 'AT', 'BE', 'CZ', 'IE', 'PT', 'GR',
      'HU', 'RO', 'BG', 'HR', 'SI', 'SK', 'LT', 'LV', 'SG', 'HK',
      'TW', 'TH', 'VN', 'ID', 'MY', 'PH', 'AE', 'SA', 'IL', 'ZA',
      'MX', 'AR', 'CL', 'CO', 'PE', 'NZ', 'IS', 'LU', 'MT',
    };
    return validCodes.contains(code.toUpperCase());
  }

  String? _flagEmojiToCountryCode(String emoji) {
    if (emoji.length < 2) return null;

    try {
      final runes = emoji.runes.toList();
      if (runes.length < 2) return null;

      final firstChar = runes[0];
      final secondChar = runes[1];

      if (firstChar < 0x1F1E6 || firstChar > 0x1F1FF) return null;
      if (secondChar < 0x1F1E6 || secondChar > 0x1F1FF) return null;

      final first = String.fromCharCode(firstChar - 0x1F1E6 + 65);
      final second = String.fromCharCode(secondChar - 0x1F1E6 + 65);

      return first + second;
    } catch (e) {
      return null;
    }
  }

  String get displayName {
    try {
      final uri = Uri.parse(config);
      if (uri.fragment.isNotEmpty) {
        return Uri.decodeComponent(uri.fragment);
      }
      return uri.host;
    } catch (e) {
      return 'Unknown Server';
    }
  }

  /// Название без кода страны и emoji-флагов
  String get cleanDisplayName {
    var name = displayName;

    // Убираем emoji-флаги (пара regional-indicator символов)
    name = name.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true), '');

    // Убираем [JP], (JP), |JP|
    name = name.replaceAll(RegExp(r'[\[\(|]\s*[A-Z]{2}\s*[\]\)|]'), '');

    final validCodes = {
      'FI','EE','US','RU','DE','GB','JP','CN','KR','NL','SE','NO','DK','PL',
      'ES','IT','FR','CA','AU','BR','IN','TR','UA','CH','AT','BE','CZ','IE',
      'PT','GR','HU','RO','BG','HR','SI','SK','LT','LV','SG','HK','TW','TH',
      'VN','ID','MY','PH','AE','SA','IL','ZA','MX','AR','CL','CO','PE','NZ',
      'IS','LU','MT',
    };

    // Код в начале: "JP Название"
    final startMatch = RegExp(r'^([A-Z]{2})\s+').firstMatch(name);
    if (startMatch != null && validCodes.contains(startMatch.group(1))) {
      name = name.substring(startMatch.end);
    }

    // Код в конце: "Название JP"
    final endMatch = RegExp(r'\s+([A-Z]{2})$').firstMatch(name);
    if (endMatch != null && validCodes.contains(endMatch.group(1))) {
      name = name.substring(0, endMatch.start);
    }

    // Остаточные разделители
    name = name.replaceAll(RegExp(r'^\s*[|\u2013\u2014\-]\s*'), '');
    name = name.replaceAll(RegExp(r'\s*[|\u2013\u2014\-]\s*$'), '');
    name = name.trim();

    return name.isEmpty ? displayName : name;
  }

  String get countryFlag {
    final code = countryCode;

    if (code == null || code.length != 2) {
      return '🌐';
    }

    try {
      final firstLetter = code.codeUnitAt(0);
      final secondLetter = code.codeUnitAt(1);

      if (firstLetter < 65 || firstLetter > 90 || secondLetter < 65 || secondLetter > 90) {
        return '🌐';
      }

      final firstRegional = 0x1F1E6 + (firstLetter - 65);
      final secondRegional = 0x1F1E6 + (secondLetter - 65);

      return String.fromCharCodes([firstRegional, secondRegional]);
    } catch (e) {
      return '🌐';
    }
  }
}

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

class UnifiedStorage {
  static const String _serversFile = 'servers.json';
  static const String _subscriptionsFile = 'subscriptions.json';
  static const String _lastServerFile = 'last_server.txt';

  static List<ServerItem>? _cachedServers;
  static DateTime? _serversLastModified;

  static List<Subscription>? _cachedSubscriptions;
  static DateTime? _subscriptionsLastModified;

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
      print('Ошибка загрузки серверов: $e');
      return [];
    }
  }

  static Future<List<ServerItem>> getCachedServers() async {
    try {
      final filePath = await PortableStorage.getFilePath(_serversFile);
      final file = File(filePath);

      if (!await file.exists()) {
        _cachedServers = [];
        return [];
      }

      final lastModified = await file.lastModified();

      if (_cachedServers != null &&
          _serversLastModified != null &&
          lastModified == _serversLastModified) {
        return List.from(_cachedServers!);
      }

      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      final servers = jsonList.map((json) => ServerItem.fromJson(json)).toList();

      _cachedServers = servers;
      _serversLastModified = lastModified;

      return List.from(servers);
    } catch (e) {
      print('Ошибка загрузки серверов: $e');
      return [];
    }
  }

  static Future<void> saveServers(List<ServerItem> servers) async {
    try {
      final filePath = await PortableStorage.getFilePath(_serversFile);
      final file = File(filePath);
      final jsonList = servers.map((s) => s.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));

      _cachedServers = List.from(servers);
      _serversLastModified = await file.lastModified();
    } catch (e) {
      print('Ошибка сохранения серверов: $e');
      throw Exception('Не удалось сохранить серверы');
    }
  }

  static Future<ServerItem> addManualServer(String config) async {
    final servers = await getCachedServers();

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
    final servers = await getCachedServers();
    servers.removeWhere((s) => s.id == id);
    await saveServers(servers);
  }

  static Future<void> toggleFavorite(String serverId) async {
    final servers = await getCachedServers();
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
    final servers = await getCachedServers();
    return servers.where((s) => s.type == ServerItemType.manual).toList();
  }

  static Future<List<ServerItem>> getSubscriptionServers(String subscriptionId) async {
    final servers = await getCachedServers();
    return servers.where((s) =>
    s.type == ServerItemType.subscription &&
        s.subscriptionId == subscriptionId
    ).toList();
  }

  static Future<List<ServerItem>> getFavoriteServers() async {
    final servers = await getCachedServers();
    return servers.where((s) => s.isFavorite).toList();
  }

  static Future<void> saveLastServer(String serverId) async {
    try {
      final filePath = await PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);
      await file.writeAsString(serverId);
    } catch (e) {
      print('Ошибка сохранения последнего сервера: $e');
    }
  }

  static Future<String?> loadLastServer() async {
    try {
      final filePath = await PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);

      if (!await file.exists()) return null;

      return await file.readAsString();
    } catch (e) {
      print('Ошибка загрузки последнего сервера: $e');
      return null;
    }
  }

  static Future<ServerItem?> getLastServer() async {
    try {
      final lastId = await loadLastServer();
      if (lastId == null) return null;

      final servers = await getCachedServers();
      return servers.cast<ServerItem?>().firstWhere(
            (s) => s?.id == lastId,
        orElse: () => null,
      );
    } catch (e) {
      print('Ошибка получения последнего сервера: $e');
      return null;
    }
  }

  static Future<List<Subscription>> loadSubscriptions() async {
    try {
      final filePath = await PortableStorage.getFilePath(_subscriptionsFile);
      final file = File(filePath);

      if (!await file.exists()) {
        _cachedSubscriptions = [];
        return [];
      }

      final lastModified = await file.lastModified();

      if (_cachedSubscriptions != null &&
          _subscriptionsLastModified != null &&
          lastModified == _subscriptionsLastModified) {
        return List.from(_cachedSubscriptions!);
      }

      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      final subscriptions = jsonList.map((json) => Subscription.fromJson(json)).toList();

      _cachedSubscriptions = subscriptions;
      _subscriptionsLastModified = lastModified;

      return List.from(subscriptions);
    } catch (e) {
      print('Ошибка загрузки подписок: $e');
      return [];
    }
  }

  static Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    try {
      final filePath = await PortableStorage.getFilePath(_subscriptionsFile);
      final file = File(filePath);
      final jsonList = subscriptions.map((sub) => sub.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));

      _cachedSubscriptions = List.from(subscriptions);
      _subscriptionsLastModified = await file.lastModified();
    } catch (e) {
      print('Ошибка сохранения подписок: $e');
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

    final servers = await getCachedServers();
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
    final servers = await getCachedServers();

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

  static Future<void> migrateFromOldFormat() async {
    try {
      final servers = await getCachedServers();
      if (servers.isNotEmpty) {
        return;
      }
    } catch (e) {
      print('Ошибка миграции: $e');
    }
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}