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
  static bool _isSafeUrl(String url) {
    try {
      final uri = Uri.parse(url);

      // Проверка, только HTTP/HTTPS
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return false;
      }

      // Проверка наличия хоста
      if (uri.host.isEmpty) {
        return false;
      }

      // Блокировка локальных адресов
      final host = uri.host.toLowerCase();

      // Блокируем localhost
      if (host == 'localhost' ||
          host == '127.0.0.1' ||
          host.startsWith('127.') ||
          host == '0.0.0.0' ||
          host == '::1') {
        return false;
      }

      // Блокируем локальные сети
      final ipPatterns = [
        RegExp(r'^10\.'),
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.'),
        RegExp(r'^192\.168\.'),
        RegExp(r'^169\.254\.'),
        RegExp(r'^fc00:'),
        RegExp(r'^fe80:'),
      ];

      for (final pattern in ipPatterns) {
        if (pattern.hasMatch(host)) {
          return false;
        }
      }

      // Блокируем metadata endpoints
      if (host == '169.254.169.254' || host.contains('metadata')) {
        return false;
      }

      // Длина URL не должна превышать разумных пределов
      if (url.length > 2048) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Загрузить подписки
  static Future<List<Subscription>> loadSubscriptions() async {
    return await UnifiedStorage.loadSubscriptions();
  }

  /// Сохранить подписки
  static Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    await UnifiedStorage.saveSubscriptions(subscriptions);
  }

  /// Добавить подписку
  static Future<Subscription> addSubscription({
    required String name,
    required String url,
    bool autoUpdate = true,
  }) async {
    // Валидация URL
    if (!_isValidUrl(url)) {
      throw Exception('Некорректный URL подписки');
    }

    // БЕЗОПАСНОСТЬ: Проверка на SSRF
    if (!_isSafeUrl(url)) {
      throw SecurityException('Запрещенный URL: попытка доступа к локальным ресурсам');
    }

    return await UnifiedStorage.addSubscription(
      name: name,
      url: url,
      autoUpdate: autoUpdate,
    );
  }

  /// Удалить подписку
  static Future<void> deleteSubscription(String id) async {
    await UnifiedStorage.deleteSubscription(id);
  }

  /// Обновить подписку
  static Future<Subscription> updateSubscription(Subscription subscription) async {
    return await UnifiedStorage.updateSubscription(subscription);
  }

  /// Валидация URL
  static bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Скачать серверы из подписки
  static Future<List<String>> fetchServersFromSubscription(
      String url, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    try {
      // БЕЗОПАСНОСТЬ: Проверка URL перед запросом
      if (!_isSafeUrl(url)) {
        throw SecurityException('Запрещенный URL: попытка доступа к локальным ресурсам');
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
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      // БЕЗОПАСНОСТЬ: Проверка размера ответа (защита от DoS)
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
    } on SecurityException {
      rethrow;
    } catch (e) {
      throw Exception('Не удалось загрузить подписку: ${e.toString()}');
    }
  }

  /// Парсинг содержимого подписки
  static List<String> _parseSubscriptionContent(String content) {
    final servers = <String>[];

    try {
      String decodedContent;

      // Пробуем декодировать из base64
      try {
        final trimmed = content.trim();
        final cleaned = trimmed.replaceAll(RegExp(r'\s'), '');
        decodedContent = utf8.decode(base64.decode(cleaned));
      } catch (e) {
        decodedContent = content;
      }

      // Парсим строки
      final lines = decodedContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);

      for (final line in lines) {
        if (_isValidServerConfig(line)) {
          servers.add(line);
        }
      }

    } catch (e) {
      throw Exception('Не удалось распарсить подписку');
    }

    return servers;
  }

  /// Проверка валидности конфига сервера
  static bool _isValidServerConfig(String config) {
    return config.startsWith('vless://') ||
        config.startsWith('vmess://') ||
        config.startsWith('trojan://') ||
        config.startsWith('ss://') ||
        config.startsWith('ssr://');
  }

  /// Обновить серверы подписки
  static Future<UpdateResult> updateSubscriptionServers(
      Subscription subscription,
      ) async {
    try {
      // Скачиваем новые серверы
      final newServers = await fetchServersFromSubscription(subscription.url);

      // Обновляем серверы в хранилище
      await UnifiedStorage.updateSubscriptionServers(
        subscriptionId: subscription.id,
        subscriptionName: subscription.name,
        newConfigs: newServers,
      );

      // Обновляем метаданные подписки
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

  /// Обновить все подписки с автообновлением
  static Future<List<UpdateResult>> updateAllSubscriptions() async {
    final subscriptions = await loadSubscriptions();
    final results = <UpdateResult>[];

    for (final subscription in subscriptions) {
      if (subscription.autoUpdate) {
        results.add(await updateSubscriptionServers(subscription));
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return results;
  }

  /// Получить подписки, которые нужно обновить
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

  /// Удалить серверы подписки (используется при удалении подписки)
  static Future<void> removeSubscriptionServers(Subscription subscription) async {
    await UnifiedStorage.deleteSubscription(subscription.id);
  }
}