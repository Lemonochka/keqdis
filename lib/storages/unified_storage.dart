import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../utils/security_hardening.dart';

class PortableStorage {
  static String? _portableDir;

  static bool _isValidFilename(String filename) {
    if (filename.contains('..') ||
        filename.contains('/') ||
        filename.contains('\\')) {
      return false;
    }
    if (path.isAbsolute(filename)) {
      return false;
    }
    if (filename.contains(':') ||
        filename.contains('|') ||
        filename.contains('<') ||
        filename.contains('>')) {
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

  static String getFilePath(String filename) {
    if (!_isValidFilename(filename)) {
      throw ArgumentError('Недопустимое имя файла: $filename');
    }
    if (_portableDir == null) {
      throw StateError(
        'Portable directory not initialized. Call getPortableDirectory() first.',
      );
    }
    return path.join(_portableDir!, filename);
  }
}

enum ServerItemType { manual, subscription }

class ServerItem {
  final String id;
  final String config;
  final ServerItemType type;
  final String? subscriptionId;
  final String? subscriptionName;
  final DateTime addedAt;
  final bool isFavorite;

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
      addedAt: json['addedAt'] != null
          ? DateTime.parse(json['addedAt'])
          : DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  ServerItem copyWith({bool? isFavorite}) {
    return ServerItem(
      id: id,
      config: config,
      type: type,
      subscriptionId: subscriptionId,
      subscriptionName: subscriptionName,
      addedAt: addedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  String get stableKey {
    try {
      final uri = Uri.parse(config);
      final host = uri.host.toLowerCase();
      final port = uri.port.toString();

      if (config.startsWith('vmess://')) {
        try {
          final payload = config.substring('vmess://'.length).trim();
          final normalized = base64.normalize(payload);
          final decoded = utf8.decode(base64.decode(normalized));
          final json = jsonDecode(decoded) as Map<String, dynamic>;
          final id = (json['id'] as String? ?? '').toLowerCase();
          final add = (json['add'] as String? ?? '').toLowerCase();
          final portJ = json['port']?.toString() ?? port;
          return 'vmess:$id@$add:$portJ';
        } catch (_) {
          return 'vmess:@$host:$port';
        }
      }

      final userInfo = uri.userInfo.toLowerCase();
      return '${uri.scheme}:$userInfo@$host:$port';
    } catch (_) {
      final noFragment = config.split('#').first;
      final end = noFragment.length > 80 ? 80 : noFragment.length;
      return noFragment.substring(0, end);
    }
  }

  String get displayName {
    if (_cachedDisplayName != null) return _cachedDisplayName!;
    try {
      final uri = Uri.parse(config);
      if (uri.fragment.isNotEmpty) {
        _cachedDisplayName = Uri.decodeComponent(uri.fragment);
      } else {
        _cachedDisplayName = uri.host;
      }
    } catch (e) {
      _cachedDisplayName = 'Unknown Server';
    }
    return _cachedDisplayName!;
  }
}

class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime lastUpdated;
  final bool autoUpdate;
  final int serverCount;
  final int? trafficUploadBytes;
  final int? trafficDownloadBytes;
  final int? trafficTotalBytes;
  final DateTime? expiresAt;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.lastUpdated,
    this.autoUpdate = true,
    this.serverCount = 0,
    this.trafficUploadBytes,
    this.trafficDownloadBytes,
    this.trafficTotalBytes,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'lastUpdated': lastUpdated.toIso8601String(),
    'autoUpdate': autoUpdate,
    'serverCount': serverCount,
    'trafficUploadBytes': trafficUploadBytes,
    'trafficDownloadBytes': trafficDownloadBytes,
    'trafficTotalBytes': trafficTotalBytes,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      autoUpdate: json['autoUpdate'] as bool? ?? true,
      serverCount: json['serverCount'] as int? ?? 0,
      trafficUploadBytes: json['trafficUploadBytes'] as int?,
      trafficDownloadBytes: json['trafficDownloadBytes'] as int?,
      trafficTotalBytes: json['trafficTotalBytes'] as int?,
      expiresAt: json['expiresAt'] is String
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
    );
  }

  Subscription copyWith({
    String? name,
    String? url,
    DateTime? lastUpdated,
    bool? autoUpdate,
    int? serverCount,
    int? trafficUploadBytes,
    int? trafficDownloadBytes,
    int? trafficTotalBytes,
    DateTime? expiresAt,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      serverCount: serverCount ?? this.serverCount,
      trafficUploadBytes: trafficUploadBytes ?? this.trafficUploadBytes,
      trafficDownloadBytes: trafficDownloadBytes ?? this.trafficDownloadBytes,
      trafficTotalBytes: trafficTotalBytes ?? this.trafficTotalBytes,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class UnifiedStorage {
  static const String _serversFile = 'servers.json';
  static const String _subscriptionsFile = 'subscriptions.json';
  static const String _lastServerFile = 'last_server.txt';

  static List<ServerItem> _servers = [];
  static List<Subscription> _subscriptions = [];
  static bool _isInitialized = false;

  // FIX: Простая очередь операций для предотвращения race condition при параллельных записях
  static Completer<void>? _operationLock;

  static Future<T> _withLock<T>(Future<T> Function() action) async {
    // Ждём завершения предыдущей операции
    while (_operationLock != null && !_operationLock!.isCompleted) {
      await _operationLock!.future;
    }
    _operationLock = Completer<void>();
    try {
      return await action();
    } finally {
      _operationLock!.complete();
    }
  }

  static Future<void> init() async {
    if (_isInitialized) return;
    await PortableStorage.getPortableDirectory();
    await _loadAllFromDisk();
    _isInitialized = true;
  }

  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  static Future<void> _loadAllFromDisk() async {
    _servers = await _loadGenericList(_serversFile, ServerItem.fromJson);
    _subscriptions = await _loadGenericList(
      _subscriptionsFile,
      Subscription.fromJson,
    );
  }

  static Future<List<T>> _loadGenericList<T>(
    String fileName,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final filePath = PortableStorage.getFilePath(fileName);
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final List<dynamic> jsonList = json.decode(content);
      return jsonList
          .map((json) => fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, s) {
      debugPrint('Failed to load $fileName: $e\n$s');
      return [];
    }
  }

  static Future<void> _saveServers() async {
    await _saveGenericList(_serversFile, _servers);
  }

  static Future<void> _saveSubscriptions() async {
    await _saveGenericList(_subscriptionsFile, _subscriptions);
  }

  static Future<void> _saveGenericList<T extends dynamic>(
    String fileName,
    List<T> list,
  ) async {
    try {
      final filePath = PortableStorage.getFilePath(fileName);
      final jsonList = list.map((item) => item.toJson()).toList();
      await SecurityHardening.writeStringAtomically(
        filePath,
        json.encode(jsonList),
      );
    } catch (e, s) {
      debugPrint('Failed to save $fileName: $e\n$s');
    }
  }

  static Future<List<ServerItem>> getServers() async {
    await _ensureInitialized();
    return _servers;
  }

  static Future<List<Subscription>> getSubscriptions() async {
    await _ensureInitialized();
    return _subscriptions;
  }

  // FIX: Обернули мутирующие операции в _withLock
  static Future<ServerItem> addManualServer(String config) async {
    return _withLock(() async {
      await _ensureInitialized();
      if (_servers.any((s) => s.config == config)) {
        throw Exception('Этот сервер уже добавлен');
      }
      // FIX: Добавляем рандомную часть к ID для уникальности при быстром добавлении
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp * 31) % 99999; // простой pseudo-random
      final item = ServerItem(
        id: '${timestamp}_$random',
        config: config,
        type: ServerItemType.manual,
      );
      _servers.add(item);
      await _saveServers();
      return item;
    });
  }

  static Future<void> deleteServer(String id) async {
    return _withLock(() async {
      await _ensureInitialized();
      _servers.removeWhere((s) => s.id == id);
      await _saveServers();
    });
  }

  static Future<void> toggleFavorite(String serverId) async {
    return _withLock(() async {
      await _ensureInitialized();
      final index = _servers.indexWhere((s) => s.id == serverId);
      if (index != -1) {
        _servers[index] = _servers[index].copyWith(
          isFavorite: !_servers[index].isFavorite,
        );
        await _saveServers();
      }
    });
  }

  static Future<void> saveLastServer(String? serverId) async {
    await _ensureInitialized();
    try {
      final filePath = PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);
      if (serverId == null) {
        if (await file.exists()) await file.delete();
      } else {
        await SecurityHardening.writeStringAtomically(filePath, serverId);
      }
    } catch (e) {
      debugPrint('Failed to save last server ID: $e');
    }
  }

  static Future<String?> loadLastServerId() async {
    await _ensureInitialized();
    try {
      final filePath = PortableStorage.getFilePath(_lastServerFile);
      final file = File(filePath);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  static Future<Subscription> addSubscription({
    required String name,
    required String url,
    bool autoUpdate = true,
  }) async {
    return _withLock(() async {
      await _ensureInitialized();
      if (_subscriptions.any((sub) => sub.url == url)) {
        throw Exception('Подписка с таким URL уже существует');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (timestamp * 31) % 99999;
      final subscription = Subscription(
        id: '${timestamp}_$random',
        name: name,
        url: url,
        lastUpdated: DateTime.now().subtract(const Duration(days: 1)),
        autoUpdate: autoUpdate,
      );
      _subscriptions.add(subscription);
      await _saveSubscriptions();
      return subscription;
    });
  }

  static Future<void> deleteSubscription(String subscriptionId) async {
    return _withLock(() async {
      await _ensureInitialized();
      _subscriptions.removeWhere((sub) => sub.id == subscriptionId);
      _servers.removeWhere((s) => s.subscriptionId == subscriptionId);
      await Future.wait([_saveSubscriptions(), _saveServers()]);
    });
  }

  static Future<Subscription> updateSubscription(
    Subscription subscription,
  ) async {
    return _withLock(() async {
      await _ensureInitialized();
      final index = _subscriptions.indexWhere(
        (sub) => sub.id == subscription.id,
      );
      if (index != -1) {
        _subscriptions[index] = subscription;
        await _saveSubscriptions();
        return subscription;
      } else {
        throw Exception('Подписка не найдена');
      }
    });
  }

  static Future<void> reorderSubscriptions(List<String> orderedIds) async {
    return _withLock(() async {
      await _ensureInitialized();
      if (_subscriptions.isEmpty) return;

      final orderMap = <String, int>{
        for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
      };

      _subscriptions.sort((a, b) {
        final ai = orderMap[a.id] ?? 1 << 20;
        final bi = orderMap[b.id] ?? 1 << 20;
        return ai.compareTo(bi);
      });

      await _saveSubscriptions();
    });
  }

  static Future<void> updateSubscriptionServers({
    required String subscriptionId,
    required String subscriptionName,
    required List<String> newConfigs,
  }) async {
    return _withLock(() async {
      await _ensureInitialized();
      final oldServers =
          _servers.where((s) => s.subscriptionId == subscriptionId).toList();
      final oldByStable = <String, ServerItem>{
        for (final s in oldServers) s.stableKey: s,
      };

      _servers.removeWhere((s) => s.subscriptionId == subscriptionId);
      int timestamp = DateTime.now().millisecondsSinceEpoch;
      final newServers = newConfigs.map((config) {
        final exactMatch = oldServers.cast<ServerItem?>().firstWhere(
          (s) => s?.config == config,
          orElse: () => null,
        );
        if (exactMatch != null) {
          return ServerItem(
            id: exactMatch.id,
            config: config,
            type: ServerItemType.subscription,
            subscriptionId: subscriptionId,
            subscriptionName: subscriptionName,
            addedAt: exactMatch.addedAt,
            isFavorite: exactMatch.isFavorite,
          );
        }

        final temp = ServerItem(
          id: 'tmp',
          config: config,
          type: ServerItemType.subscription,
          subscriptionId: subscriptionId,
          subscriptionName: subscriptionName,
        );
        final stableMatch = oldByStable[temp.stableKey];
        if (stableMatch != null) {
          return ServerItem(
            id: stableMatch.id,
            config: config,
            type: ServerItemType.subscription,
            subscriptionId: subscriptionId,
            subscriptionName: subscriptionName,
            addedAt: stableMatch.addedAt,
            isFavorite: stableMatch.isFavorite,
          );
        }

        return ServerItem(
          id: '${timestamp++}',
          config: config,
          type: ServerItemType.subscription,
          subscriptionId: subscriptionId,
          subscriptionName: subscriptionName,
        );
      });
      _servers.addAll(newServers);
      await _saveServers();
    });
  }
}
