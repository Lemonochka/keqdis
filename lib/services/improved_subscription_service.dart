import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../storages/unified_storage.dart';

class UpdateResult {
  final bool success;
  final int serverCount;
  final String? error;
  final Subscription subscription;

  UpdateResult({
    required this.success,
    this.serverCount = 0,
    this.error,
    required this.subscription,
  });
}

class SubscriptionService {
  static final _ipPatterns = [
    RegExp(r'^10\.'),
    RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.'),
    RegExp(r'^192\.168\.'),
    RegExp(r'^169\.254\.'),
    RegExp(r'^fc00:'),
    RegExp(r'^fe80:'),
  ];

  static bool _isSafeUrl(String url) {
    try {
      if (url.length > 2048) {
        return false;
      }

      final uri = Uri.parse(url);

      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return false;
      }

      if (uri.host.isEmpty) {
        return false;
      }

      final host = uri.host.toLowerCase();

      if (host == 'localhost' ||
          host == '127.0.0.1' ||
          host.startsWith('127.') ||
          host == '0.0.0.0' ||
          host == '::1' ||
          host == '169.254.169.254' ||
          host.contains('metadata')) {
        return false;
      }

      for (final pattern in _ipPatterns) {
        if (pattern.hasMatch(host)) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Subscription>> loadSubscriptions() async {
    return await UnifiedStorage.getSubscriptions();
  }

  static Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    // This method is no longer needed as UnifiedStorage handles saving internally.
  }

  static Future<Subscription> addSubscription({
    required String name,
    required String url,
    bool autoUpdate = true,
  }) async {
    if (!_isValidUrl(url)) {
      throw ArgumentError('Некорректный URL подписки');
    }

    if (!_isSafeUrl(url)) {
      throw Exception('Запрещенный URL: попытка доступа к локальным ресурсам');
    }

    return await UnifiedStorage.addSubscription(
      name: name,
      url: url,
      autoUpdate: autoUpdate,
    );
  }

  static Future<void> deleteSubscription(String id) async {
    await UnifiedStorage.deleteSubscription(id);
  }

  static Future<Subscription> updateSubscription(Subscription subscription) async {
    return await UnifiedStorage.updateSubscription(subscription);
  }

  static bool _isValidUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<List<String>> fetchServersFromSubscription(
      String url, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    try {
      if (!_isSafeUrl(url)) {
        throw Exception('Запрещенный URL: попытка доступа к локальным ресурсам');
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      if (response.contentLength != null && response.contentLength! > 10 * 1024 * 1024) {
        throw Exception('Ответ слишком большой (максимум 10MB)');
      }

      final servers = _parseSubscriptionContent(response.body);

      if (servers.isEmpty) {
        throw Exception('В подписке не найдено серверов');
      }

      return servers;

    } on SocketException catch (e) {
      throw Exception('Ошибка сети: ${e.message}');
    } on TimeoutException {
      throw Exception('Превышено время ожидания');
    } on HttpException catch (e) {
      throw Exception('HTTP ошибка: ${e.message}');
    } on FormatException catch (e) {
      throw Exception('Ошибка формата данных: ${e.message}');
    } catch (e) {
      throw Exception('Не удалось загрузить подписку: ${e.toString()}');
    }
  }

  static List<String> _parseSubscriptionContent(String content) {
    final servers = <String>[];

    try {
      String decodedContent;

      try {
        decodedContent = utf8.decode(base64.decode(content.trim()));
      } on FormatException {
        decodedContent = content; // Not a base64 string, assume plain text
      }

      final lines = LineSplitter.split(decodedContent)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);

      for (final line in lines) {
        if (_isValidServerConfig(line)) {
          servers.add(line);
        }
      }

    } on FormatException catch(e) {
       throw FormatException('Не удалось распознать содержимое подписки: ${e.message}');
    } catch (e) {
      throw Exception('Не удалось распарсить подписку');
    }

    return servers;
  }

  static bool _isValidServerConfig(String config) {
    return config.startsWith('vless://') ||
        config.startsWith('vmess://') ||
        config.startsWith('trojan://') ||
        config.startsWith('ss://') ||
        config.startsWith('ssr://');
  }

  static Future<UpdateResult> updateSubscriptionServers(
      Subscription subscription,
      ) async {
    try {
      final newServers = await fetchServersFromSubscription(subscription.url);

      await UnifiedStorage.updateSubscriptionServers(
        subscriptionId: subscription.id,
        subscriptionName: subscription.name,
        newConfigs: newServers,
      );

      final updatedSubscription = subscription.copyWith(
        lastUpdated: DateTime.now(),
        serverCount: newServers.length,
      );

      await updateSubscription(updatedSubscription);

      return UpdateResult(
        success: true,
        serverCount: newServers.length,
        subscription: updatedSubscription,
      );

    } catch (e) {
      return UpdateResult(
        success: false,
        error: e.toString(),
        subscription: subscription,
      );
    }
  }

  static Future<List<UpdateResult>> updateAllSubscriptions() async {
    final subscriptions = await loadSubscriptions();
    final tasks = <Future<UpdateResult>>[];

    for (final subscription in subscriptions) {
      if (subscription.autoUpdate) {
        tasks.add(updateSubscriptionServers(subscription));
      }
    }

    final results = await Future.wait(tasks.map((task) => task.catchError((e) {
      return UpdateResult(success: false, error: e.toString(), subscription: Subscription(id: 'unknown', name: 'unknown', url: '', lastUpdated: DateTime.now()));
    })));

    return results.whereType<UpdateResult>().toList();
  }

  static Future<List<Subscription>> getSubscriptionsDueForUpdate({
    Duration interval = const Duration(hours: 12),
  }) async {
    final subscriptions = await loadSubscriptions();
    final now = DateTime.now();

    return subscriptions.where((sub) {
      if (!sub.autoUpdate) return false;
      return now.difference(sub.lastUpdated) >= interval;
    }).toList();
  }

  static Future<void> removeSubscriptionServers(Subscription subscription) async {
    await UnifiedStorage.deleteSubscription(subscription.id);
  }
}
