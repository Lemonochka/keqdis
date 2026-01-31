import 'dart:convert';
import 'improved_settings_storage.dart';

class ConfigGenerator {
  /// БЕЗОПАСНОСТЬ: Валидация VLESS URL
  static bool _isValidVlessUrl(String url) {
    try {
      if (!url.startsWith('vless://')) return false;

      final uri = Uri.parse(url);

      // Проверка обязательных компонентов
      if (uri.userInfo.isEmpty) return false;
      if (uri.host.isEmpty) return false;
      if (uri.port <= 0 || uri.port > 65535) return false;

      // UUID проверка
      final uuid = uri.userInfo;
      final uuidWithDashes = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false
      );
      final uuidWithoutDashes = RegExp(
          r'^[0-9a-f]{32}$',
          caseSensitive: false
      );

      if (!uuidWithDashes.hasMatch(uuid) && !uuidWithoutDashes.hasMatch(uuid)) {
        print('⚠️ Некорректный UUID: $uuid');
        return false;
      }

      return true;
    } catch (e) {
      print('⚠️ Ошибка валидации VLESS URL: $e');
      return false;
    }
  }

  /// Генерация конфига с валидацией
  static String generateConfig(String input, AppSettings settings) {
    try {
      final trimmed = input.trim();

      // БЕЗОПАСНОСТЬ: Ограничение длины входных данных
      if (trimmed.length > 4096) {
        throw Exception("Конфиг слишком длинный");
      }

      if (trimmed.startsWith("vless://")) {
        if (!_isValidVlessUrl(trimmed)) {
          throw Exception("Некорректный VLESS URL");
        }
        return _parseVless(trimmed, settings);
      } else {
        throw Exception("Поддерживается только VLESS");
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception("Ошибка генерации конфига");
    }
  }

  static String _parseVless(String link, AppSettings settings) {
    try {
      var uri = Uri.parse(link);
      String uuid = uri.userInfo;
      String address = uri.host;
      int port = uri.port;
      Map<String, String> q = uri.queryParameters;

      print('🔍 Парсинг VLESS: $address:$port');
      print('   Type: ${q['type']} | Security: ${q['security']}');

      // Валидация
      if (!_isValidAddress(address)) {
        throw Exception("Недопустимый адрес сервера");
      }
      if (port <= 0 || port > 65535) {
        throw Exception("Недопустимый порт");
      }

      Map<String, dynamic> outbound = {
        "protocol": "vless",
        "tag": "proxy",
        "settings": {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": uuid,
                  "encryption": "none",
                  "flow": _sanitizeString(q['flow'] ?? "")
                }
              ]
            }
          ]
        },
        "streamSettings": <String, dynamic>{}
      };

      var stream = outbound['streamSettings'] as Map<String, dynamic>;

      // Валидация и установка типа сети
      String network = _sanitizeString(q['type'] ?? "tcp");
      if (!_isValidNetworkType(network)) {
        network = "tcp";
      }
      stream['network'] = network;

      // Валидация security
      String security = _sanitizeString(q['security'] ?? "none");
      if (!_isValidSecurityType(security)) {
        security = "none";
      }
      stream['security'] = security;

      // Настройка TLS
      if (security == 'tls') {
        final sni = _sanitizeString(q['sni'] ?? q['host'] ?? address);
        final alpnString = _sanitizeString(q['alpn'] ?? '');
        final fp = _sanitizeString(q['fp'] ?? '');

        stream['tlsSettings'] = {
          "serverName": sni,
          "allowInsecure": false,
        };

        if (alpnString.isNotEmpty) {
          stream['tlsSettings']['alpn'] = alpnString.split(',');
        }

        if (fp.isNotEmpty && _isValidFingerprint(fp)) {
          stream['tlsSettings']['fingerprint'] = fp;
        }
      }
      // Настройка Reality
      else if (security == 'reality') {
        final sni = _sanitizeString(q['sni'] ?? q['host'] ?? "google.com");
        final fp = _sanitizeString(q['fp'] ?? "chrome");
        final pbk = _sanitizeString(q['pbk'] ?? "");
        final sid = _sanitizeString(q['sid'] ?? "");
        final spx = _sanitizeString(q['spx'] ?? "");

        print('🔐 Reality: SNI=$sni, FP=$fp');

        stream['realitySettings'] = {
          "show": false,
          "fingerprint": _isValidFingerprint(fp) ? fp : "chrome",
          "serverName": sni,
          "publicKey": pbk,
          "shortId": sid,
        };

        if (spx.isNotEmpty) {
          stream['realitySettings']['spiderX'] = spx;
        }
      }

      // Настройка транспортов
      if (network == 'tcp' && q['headerType'] == 'http') {
        final host = _sanitizeString(q['host'] ?? address);
        stream['tcpSettings'] = {
          "header": {
            "type": "http",
            "request": {
              "headers": {
                "Host": [host]
              }
            }
          }
        };
      }
      else if (network == 'ws') {
        final wsPath = _sanitizeString(q['path'] ?? "/");
        final host = _sanitizeString(q['host'] ?? q['sni'] ?? address);

        stream['wsSettings'] = {
          "path": wsPath,
          "headers": {
            "Host": host
          }
        };
      }
      else if (network == 'grpc') {
        final serviceName = _sanitizeString(q['serviceName'] ?? "");
        final mode = _sanitizeString(q['mode'] ?? "");

        stream['grpcSettings'] = {
          "serviceName": serviceName,
          "multiMode": (mode == 'multi')
        };
      }
      // XHTTP - ПРАВИЛЬНАЯ реализация согласно документации Xray
      else if (network == 'xhttp') {
        final xhttpPath = _sanitizeString(q['path'] ?? "/");
        final host = _sanitizeString(q['host'] ?? "");
        final mode = _sanitizeString(q['mode'] ?? "auto");

        print('🌐 XHTTP конфигурация:');
        print('   Path: $xhttpPath');
        print('   Host: ${host.isEmpty ? "(не указан)" : host}');
        print('   Mode: $mode');

        // ВАЖНО: для xhttp используется xhttpSettings, а не httpupgradeSettings
        final xhttpSettings = <String, dynamic>{
          "path": xhttpPath,
        };

        // Host добавляем только если указан
        if (host.isNotEmpty) {
          xhttpSettings['host'] = host;
        }

        // Mode: stream-up, packet-up, auto
        if (mode.isNotEmpty && ['stream-up', 'packet-up', 'auto'].contains(mode)) {
          xhttpSettings['mode'] = mode;
        }

        stream['xhttpSettings'] = xhttpSettings;

        print('✅ xhttpSettings: ${jsonEncode(xhttpSettings)}');
      }
      // HTTPUpgrade (старый протокол, рекомендуется переход на xhttp)
      else if (network == 'httpupgrade') {
        final httpPath = _sanitizeString(q['path'] ?? "/");
        final host = _sanitizeString(q['host'] ?? "");

        final httpSettings = <String, dynamic>{
          "path": httpPath,
        };

        if (host.isNotEmpty) {
          httpSettings['host'] = host;
        }

        stream['httpupgradeSettings'] = httpSettings;
      }
      // SplitHTTP
      else if (network == 'splithttp') {
        final splitPath = _sanitizeString(q['path'] ?? "/");
        final host = _sanitizeString(q['host'] ?? "");

        final splitSettings = <String, dynamic>{
          "path": splitPath,
        };

        if (host.isNotEmpty) {
          splitSettings['host'] = host;
        }

        stream['splithttpSettings'] = splitSettings;
      }
      // HTTP/2
      else if (network == 'h2' || network == 'http') {
        final h2Path = _sanitizeString(q['path'] ?? "/");
        final host = _sanitizeString(q['host'] ?? q['sni'] ?? address);

        stream['network'] = 'h2';
        stream['httpSettings'] = {
          "path": h2Path,
          "host": [host],
        };
      }

      final configJson = _buildXrayConfig(outbound, settings);
      print('📄 Конфиг готов (${configJson.length} байт)');

      return configJson;
    } catch (e) {
      print('❌ Ошибка: $e');
      throw Exception("Ошибка парсинга VLESS: ${e.toString()}");
    }
  }

  /// Валидация адреса
  static bool _isValidAddress(String address) {
    if (address.isEmpty || address.length > 253) return false;

    // IP адрес
    final ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4Pattern.hasMatch(address)) {
      final parts = address.split('.');
      return parts.every((part) {
        final num = int.tryParse(part);
        return num != null && num >= 0 && num <= 255;
      });
    }

    // Доменное имя
    final domainPattern = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$');
    return domainPattern.hasMatch(address);
  }

  /// Валидация типа сети
  static bool _isValidNetworkType(String type) {
    const validTypes = {'tcp', 'ws', 'grpc', 'h2', 'http', 'quic', 'xhttp', 'httpupgrade', 'splithttp'};
    return validTypes.contains(type);
  }

  /// Валидация типа безопасности
  static bool _isValidSecurityType(String type) {
    const validTypes = {'none', 'tls', 'reality'};
    return validTypes.contains(type);
  }

  /// Валидация fingerprint
  static bool _isValidFingerprint(String fp) {
    const validFingerprints = {'chrome', 'firefox', 'safari', 'edge', 'ios', 'android', 'random'};
    return validFingerprints.contains(fp.toLowerCase());
  }

  /// Санитизация строк
  static String _sanitizeString(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }

  static List<String> _parseList(String raw) {
    return raw
        .split(RegExp(r'[ ,;\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => _isValidDomainOrCidr(e))
        .toList();
  }

  /// Валидация доменов и CIDR
  static bool _isValidDomainOrCidr(String input) {
    if (input.contains('/')) {
      final parts = input.split('/');
      if (parts.length != 2) return false;

      final mask = int.tryParse(parts[1]);
      if (mask == null || mask < 0 || mask > 32) return false;

      input = parts[0];
    }

    final ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipPattern.hasMatch(input)) {
      final parts = input.split('.');
      return parts.every((part) {
        final num = int.tryParse(part);
        return num != null && num >= 0 && num <= 255;
      });
    }

    final domainPattern = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$');
    return domainPattern.hasMatch(input);
  }

  static String _buildXrayConfig(Map<String, dynamic> proxyOutbound, AppSettings settings) {
    final directDomains = _parseList(settings.directDomains);
    final blockedDomains = _parseList(settings.blockedDomains);
    final proxyDomains = _parseList(settings.proxyDomains);
    final directIps = _parseList(settings.directIps);

    int localPort = settings.localPort;
    if (localPort < 1024 || localPort > 65535) {
      localPort = 2080;
    }

    Map<String, dynamic> config = {
      "log": {"loglevel": "warning"},
      "inbounds": [
        {
          "tag": "mixed-in",
          "port": localPort,
          "listen": "127.0.0.1",
          "protocol": "mixed",
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          }
        }
      ],
      "outbounds": [
        proxyOutbound,
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"}
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          if (blockedDomains.isNotEmpty)
            {"type": "field", "outboundTag": "block", "domain": blockedDomains},

          if (proxyDomains.isNotEmpty)
            {"type": "field", "outboundTag": "proxy", "domain": proxyDomains},

          if (directDomains.isNotEmpty)
            {"type": "field", "outboundTag": "direct", "domain": directDomains},

          if (directIps.isNotEmpty)
            {"type": "field", "outboundTag": "direct", "ip": directIps},

          {"type": "field", "outboundTag": "proxy", "network": "tcp,udp"}
        ]
      }
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }
}