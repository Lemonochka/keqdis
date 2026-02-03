import 'dart:async';
import 'dart:io';

enum PingType {
  tcp,
  proxy
}

class PingResult {
  final String server;
  final int? latencyMs;
  final bool success;
  final String error;

  PingResult({
    required this.server,
    this.latencyMs,
    required this.success,
    this.error = '',
  });
}

class PingService {
  static Map<String, dynamic>? _parseVlessConfig(String config) {
    try {
      if (!config.startsWith('vless://')) return null;

      final uri = Uri.parse(config);
      return {
        'address': uri.host,
        'port': uri.port,
        'name': uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : uri.host,
      };
    } catch (e) {
      return null;
    }
  }

  static Future<PingResult> pingTcp(String config, {int timeoutSeconds = 5}) async {
    final parsed = _parseVlessConfig(config);
    if (parsed == null) {
      return PingResult(
        server: config,
        success: false,
        error: 'Не удалось распарсить конфиг',
      );
    }

    final String address = parsed['address'];
    final int port = parsed['port'];
    final String name = parsed['name'];

    Socket? socket;

    try {
      final stopwatch = Stopwatch()..start();

      socket = await Socket.connect(
        address,
        port,
        timeout: Duration(seconds: timeoutSeconds),
      );

      stopwatch.stop();

      return PingResult(
        server: name,
        latencyMs: stopwatch.elapsedMilliseconds,
        success: true,
      );
    } on SocketException catch (e) {
      return PingResult(
        server: name,
        success: false,
        error: 'Не удалось подключиться: ${e.message}',
      );
    } on TimeoutException {
      return PingResult(
        server: name,
        success: false,
        error: 'Превышено время ожидания ($timeoutSeconds сек)',
      );
    } catch (e) {
      return PingResult(
        server: name,
        success: false,
        error: 'Ошибка: $e',
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static Future<PingResult> pingProxy(String config, int proxyPort, {int timeoutSeconds = 10}) async {
    final parsed = _parseVlessConfig(config);
    if (parsed == null) {
      return PingResult(
        server: config,
        success: false,
        error: 'Не удалось распарсить конфиг',
      );
    }

    final String name = parsed['name'];
    HttpClient? client;

    try {
      client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
      client.connectionTimeout = Duration(seconds: timeoutSeconds);
      client.badCertificateCallback = (_, __, ___) => true;

      final stopwatch = Stopwatch()..start();

      final req1 = await client.headUrl(Uri.parse('https://www.google.com'));
      req1.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
      req1.headers.set('Accept', '*/*');
      req1.headers.set('Connection', 'close');

      final res1 = await req1.close();
      await res1.drain();

      if (res1.statusCode >= 400) {
        stopwatch.stop();
        return PingResult(
          server: name,
          latencyMs: stopwatch.elapsedMilliseconds,
          success: false,
          error: 'Шаг 1 (TLS): HTTP ${res1.statusCode}',
        );
      }

      final req2 = await client.getUrl(Uri.parse('http://www.gstatic.com/generate_204'));
      req2.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
      req2.headers.set('Connection', 'close');

      final res2 = await req2.close();
      await res2.drain();

      stopwatch.stop();

      if (res2.statusCode == 204 || res2.statusCode == 200) {
        return PingResult(
          server: name,
          latencyMs: stopwatch.elapsedMilliseconds,
          success: true,
        );
      } else {
        return PingResult(
          server: name,
          latencyMs: stopwatch.elapsedMilliseconds,
          success: false,
          error: 'Шаг 2 (маршрут): HTTP ${res2.statusCode}',
        );
      }
    } on SocketException catch (e) {
      return PingResult(
        server: name,
        success: false,
        error: 'Подключение: ${e.message}',
      );
    } on TimeoutException {
      return PingResult(
        server: name,
        success: false,
        error: 'Превышено время ожидания',
      );
    } on HandshakeException catch (e) {
      return PingResult(
        server: name,
        success: false,
        error: 'SSL/TLS: ${e.message}',
      );
    } catch (e) {
      return PingResult(
        server: name,
        success: false,
        error: 'Ошибка: $e',
      );
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  static Future<PingResult> ping(
      String config,
      PingType type,
      {int proxyPort = 2080, int timeoutSeconds = 5}
      ) async {
    switch (type) {
      case PingType.tcp:
        return pingTcp(config, timeoutSeconds: timeoutSeconds);
      case PingType.proxy:
        return pingProxy(config, proxyPort, timeoutSeconds: timeoutSeconds * 2);
    }
  }

  static Future<List<PingResult>> pingMultiple(
      List<String> configs,
      PingType type,
      {int proxyPort = 2080, int timeoutSeconds = 5}
      ) async {
    final results = <PingResult>[];

    for (final config in configs) {
      final result = await ping(
          config,
          type,
          proxyPort: proxyPort,
          timeoutSeconds: timeoutSeconds
      );
      results.add(result);
    }

    return results;
  }
}