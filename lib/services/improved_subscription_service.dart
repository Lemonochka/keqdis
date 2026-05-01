import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../storages/unified_storage.dart';
import '../storages/improved_settings_storage.dart';

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

class SubscriptionUsageInfo {
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  const SubscriptionUsageInfo({
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expiresAt,
  });
}

class SubscriptionService {
  static const int _maxSubscriptionLines = 20000;
  static const int _maxSubscriptionLineLength = 8192;
  static const int _maxBodyBytes = 10 * 1024 * 1024;

  static final _ipPatterns = [
    RegExp(r'^10\.'),
    RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.'),
    RegExp(r'^192\.168\.'),
    RegExp(r'^169\.254\.'),
    RegExp(r'^fc00:'),
    RegExp(r'^fe80:'),
  ];

  static const _blockedHostnames = {
    'metadata.google.internal',
    '169.254.169.254',
    'fd00:ec2::254',
  };

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
          _blockedHostnames.contains(host)) {
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

  static Future<void> saveSubscriptions(
    List<Subscription> subscriptions,
  ) async {
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

  static Future<Subscription> updateSubscription(
    Subscription subscription,
  ) async {
    return await UnifiedStorage.updateSubscription(subscription);
  }

  static Future<void> reorderSubscriptions(List<String> orderedIds) async {
    await UnifiedStorage.reorderSubscriptions(orderedIds);
  }

  static bool _isValidUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static SubscriptionUsageInfo _parseUsageInfoFromHeaders(
    Map<String, String> headers,
  ) {
    String? readHeader(String key) {
      for (final e in headers.entries) {
        if (e.key.toLowerCase() == key) return e.value;
      }
      return null;
    }

    final raw = readHeader('x-subscription-userinfo') ??
        readHeader('subscription-userinfo') ??
        readHeader('userinfo') ??
        readHeader('x-userinfo');
    if (raw == null || raw.isEmpty) {
      return const SubscriptionUsageInfo();
    }

    int? upload;
    int? download;
    int? total;
    DateTime? expiresAt;

    final parts = raw.split(';');
    for (final part in parts) {
      final eqIdx = part.indexOf('=');
      if (eqIdx == -1) continue;
      final key = part.substring(0, eqIdx).trim().toLowerCase();
      final value = part.substring(eqIdx + 1).trim();
      final numValue = int.tryParse(value);
      switch (key) {
        case 'upload':
          upload = numValue;
          break;
        case 'download':
          download = numValue;
          break;
        case 'total':
          total = numValue;
          break;
        case 'expire':
          if (numValue != null && numValue > 0) {
            final dt = DateTime.fromMillisecondsSinceEpoch(numValue * 1000);
            if (dt.isAfter(DateTime(2000))) {
              expiresAt = dt;
            }
          }
          break;
      }
    }

    return SubscriptionUsageInfo(
      uploadBytes: upload,
      downloadBytes: download,
      totalBytes: total,
      expiresAt: expiresAt,
    );
  }

  static Future<(List<String>, SubscriptionUsageInfo)>
  fetchServersFromSubscription(
    String url, {
    Duration timeout = const Duration(seconds: 30),
    int attempt = 0,
    bool triedHwidQuery = false,
    bool triedUrlFallbacks = false,
  }) async {
    Future<http.Response> requestWithHeaders(
      String userAgent, {
      Duration? localTimeout,
      Map<String, String>? extraHeaders,
    }) {
      return http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': userAgent,
              'Accept': 'text/plain,*/*',
              'Accept-Language': 'en-US,en;q=0.9',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
              ...?extraHeaders,
            },
          )
          .timeout(localTimeout ?? timeout);
    }

    try {
      if (!_isSafeUrl(url)) {
        throw Exception(
          'Запрещенный URL: попытка доступа к локальным ресурсам',
        );
      }

      final settings = await SettingsStorage.loadSettings();
      final hwidHeaders = _buildHwidHeaders(settings);

      var response = await requestWithHeaders(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        extraHeaders: hwidHeaders,
      );

      if (response.contentLength != null &&
          response.contentLength! > _maxBodyBytes) {
        throw Exception('Ответ слишком большой (максимум 10MB)');
      }

      final looksHtml = _looksLikeHtml(response);
      if (looksHtml) {
        final uaFallback = await _retryWithSubscriptionUserAgents(
          url,
          timeout,
          hwidHeaders: hwidHeaders,
        );
        if (uaFallback != null) {
          response = uaFallback;
        }
      }

      List<String> servers = [];
      if (_looksLikeHtml(response)) {
        servers = _extractConfigsFromHtml(response.body) ?? const [];
        if (servers.isEmpty) {
          servers = await _crawlHtmlForSubscriptionConfigs(
            html: response.body,
            pageUrl: url,
            timeout: timeout,
            hwidHeaders: hwidHeaders,
          );
        }
      } else {
        servers = _parseSubscriptionContent(response.body);
      }

      if (servers.isEmpty && response.statusCode >= 400 && response.body.trim().isNotEmpty) {
        servers = _parseSubscriptionContent(response.body);
      }

      if (servers.isEmpty) {
        throw Exception('В подписке не найдено серверов');
      }

      final usageInfo = _parseUsageInfoFromHeaders(response.headers);
      return (servers, usageInfo);
    } on SocketException catch (e) {
      if (attempt == 0) {
        try {
          await Future.delayed(const Duration(seconds: 2));
          return await fetchServersFromSubscription(
            url,
            timeout: timeout,
            attempt: 1,
            triedHwidQuery: triedHwidQuery,
            triedUrlFallbacks: triedUrlFallbacks,
          );
        } catch (_) {}
      }
      throw Exception('Ошибка сети: ${e.message}');
    } on TimeoutException {
      if (attempt == 0) {
        try {
          await Future.delayed(const Duration(seconds: 2));
          return await fetchServersFromSubscription(
            url,
            timeout: timeout,
            attempt: 1,
            triedHwidQuery: triedHwidQuery,
            triedUrlFallbacks: triedUrlFallbacks,
          );
        } catch (_) {}
      }
      throw Exception('Превышено время ожидания');
    } on HttpException catch (e) {
      throw Exception('HTTP ошибка: ${e.message}');
    } on FormatException catch (e) {
      // 1) Universal HWID retry via query (only on HWID-gate / parse-fail markers)
      final settings = await SettingsStorage.loadSettings();
      final hwidHeaders = _buildHwidHeaders(settings);
      final hwid = settings.deviceHwid.trim();
      if (!triedHwidQuery &&
          _shouldRetryWithHwidQuery(e.toString()) &&
          hwidHeaders.isNotEmpty &&
          hwid.isNotEmpty) {
        final urlWithHwid = _appendHwidQuery(url, hwid);
        if (urlWithHwid != url) {
          try {
            return await fetchServersFromSubscription(
              urlWithHwid,
              timeout: timeout,
              attempt: 0,
              triedHwidQuery: true,
              triedUrlFallbacks: triedUrlFallbacks,
            );
          } catch (_) {}
        }
      }

      // 2) Universal URL fallbacks (trailing slash / http<->https), safe because
      //    only runs after a parse failure and only once per call chain.
      if (!triedUrlFallbacks) {
        final candidates = _fallbackUrlCandidates(
          url,
          (settings.shareDeviceHwid && hwid.isNotEmpty) ? hwid : null,
        );
        for (final candidate in candidates) {
          if (candidate == url) continue;
          try {
            return await fetchServersFromSubscription(
              candidate,
              timeout: timeout,
              attempt: 1,
              triedHwidQuery: triedHwidQuery,
              triedUrlFallbacks: true,
            );
          } catch (_) {
            // try next
          }
        }
      }
      throw Exception('Ошибка формата данных: ${e.message}');
    } catch (e) {
      throw Exception('Не удалось загрузить подписку: ${e.toString()}');
    }
  }

  static List<String> _parseSubscriptionContent(String content) {
    final original = content.trim();
    final candidates = <String>{original};

    try {
      final singleDecoded = _tryDecodeBase64Flexible(original);
      if (singleDecoded != null && singleDecoded.trim().isNotEmpty) {
        candidates.add(singleDecoded);
        final doubleDecoded = _tryDecodeBase64Flexible(singleDecoded);
        if (doubleDecoded != null && doubleDecoded.trim().isNotEmpty) {
          candidates.add(doubleDecoded);
        }
      }

      for (final candidate in candidates) {
        final candidateLower = candidate.toLowerCase();
        if (candidateLower.contains('turn on hwid') ||
            candidateLower.contains('enable hwid') ||
            candidateLower.contains('bind hwid')) {
          throw const FormatException(
            'Subscription contains only service links. Provider asks to enable/bind HWID for this client.',
          );
        }

        final directLinks = _extractUriLinks(candidate);
        if (directLinks.isNotEmpty) {
          return directLinks;
        }

        final jsonLinks = _tryExtractProxyLinksFromJson(candidate);
        if (jsonLinks.isNotEmpty) {
          return jsonLinks;
        }

        final lines = LineSplitter.split(candidate)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        final hasOnlyMetadataLinks =
            lines.isNotEmpty &&
            lines.every((l) => !_isValidServerConfig(l) || _isMetadataConfig(l));
        final hasHwidGateMarkers = lines.any(_isHwidGateConfig);

        final servers = <String>[];
        int lineCount = 0;
        for (final line in lines) {
          lineCount++;
          if (lineCount > _maxSubscriptionLines) {
            throw const FormatException('Слишком много строк в подписке');
          }
          if (line.length > _maxSubscriptionLineLength) {
            continue;
          }
          if (_isValidServerConfig(line) && !_isMetadataConfig(line)) {
            servers.add(line);
            continue;
          }
          final inlineLinks = _extractUriLinks(line);
          for (final link in inlineLinks) {
            if (!_isMetadataConfig(link)) {
              servers.add(link);
            }
          }
        }
        if (servers.isNotEmpty) {
          return servers;
        }
        if (hasHwidGateMarkers) {
          throw const FormatException(
            'Subscription contains only service links. Provider asks to enable/bind HWID for this client.',
          );
        }
        if (hasOnlyMetadataLinks && hasHwidGateMarkers) {
          throw const FormatException(
            'Subscription contains only service links. Provider asks to enable/bind HWID for this client.',
          );
        }
      }

      final unsupported = _detectUnsupportedFormat(candidates.last);
      if (unsupported != null) {
        throw FormatException(unsupported);
      }
      throw const FormatException(
        'No supported proxy links found. Expected URI lines like vless://, vmess://, trojan://, ss://, ssr://, hysteria://, hy2://',
      );
    } on FormatException catch (e) {
      throw FormatException('Не удалось распознать содержимое подписки: ${e.message}');
    } catch (_) {
      throw Exception('Не удалось распарсить подписку');
    }
  }

  static bool _looksLikeHtml(http.Response response) {
    final contentType = response.headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'content-type',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .toLowerCase();
    final body = response.body.trimLeft().toLowerCase();
    return contentType.contains('text/html') ||
        body.startsWith('<!doctype html') ||
        body.startsWith('<html');
  }

  static Future<http.Response?> _retryWithSubscriptionUserAgents(
    String url,
    Duration timeout, {
    required Map<String, String> hwidHeaders,
  }
  ) async {
    const userAgents = <String>[
      'v2rayNG/1.9.28',
      'NekoBox/1.3.9',
      'ClashMetaForAndroid/2.11.5',
      'clash-verge/v2.2.2',
      'sing-box',
      'QuantumultX',
      'Shadowrocket',
    ];
    for (final ua in userAgents) {
      try {
        final resp = await http
            .get(
              Uri.parse(url),
              headers: {
                'User-Agent': ua,
                'Accept': 'text/plain,*/*',
                ...hwidHeaders,
              },
            )
            .timeout(timeout);
        if (resp.statusCode >= 200 && resp.statusCode < 500 && !_looksLikeHtml(resp)) {
          return resp;
        }
      } catch (_) {}
    }
    return null;
  }

  static String? _tryDecodeBase64Flexible(String input) {
    final compact =
        input.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '+').replaceAll('_', '/');
    if (compact.isEmpty) return null;
    final padded = switch (compact.length % 4) {
      2 => '$compact==',
      3 => '$compact=',
      _ => compact,
    };
    try {
      return const Utf8Decoder().convert(base64.decode(base64.normalize(padded)));
    } on Object {
      return null;
    }
  }

  static String? _detectUnsupportedFormat(String content) {
    final text = content.trimLeft();
    final lower = text.toLowerCase();
    if (lower.startsWith('proxies:') ||
        lower.contains('\nproxies:') ||
        lower.startsWith('mixed-port:') ||
        lower.contains('\nproxy-providers:')) {
      return 'Unsupported subscription format: Clash YAML';
    }
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          final keys = parsed.keys.map((k) => k.toLowerCase()).toSet();
          if (keys.contains('outbounds') || keys.contains('inbounds') || keys.contains('proxies')) {
            return 'Unsupported subscription format: sing-box/V2Ray JSON';
          }
        } else if (parsed is List && parsed.isNotEmpty) {
          return 'Unsupported subscription format: JSON array config';
        }
      } on Object {}
    }
    return null;
  }

  static List<String>? _extractConfigsFromHtml(String html) {
    final candidates = <String>[];

    final blockMatches = RegExp(
      r'<(?:pre|code|textarea)[^>]*>([\s\S]*?)</(?:pre|code|textarea)>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in blockMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final scriptMatches = RegExp(
      r'<script[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in scriptMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final jsMatches = RegExp(
      r'''(?:payload|subscription|subdata|content|data)\s*[:=]\s*["']([\s\S]*?)["']''',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in jsMatches) {
      final v = m.group(1);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    final base64Like = RegExp(
      r'[A-Za-z0-9+/_=\r\n-]{300,}',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in base64Like) {
      final v = m.group(0);
      if (v != null && v.trim().isNotEmpty) candidates.add(v);
    }

    candidates.add(html);

    for (final raw in candidates) {
      final variants = <String>{raw, _htmlUnescape(raw), _jsUnescape(_htmlUnescape(raw))};
      for (final variant in variants) {
        final cleaned = variant.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
        if (cleaned.isEmpty) continue;
        final directLinks = _extractUriLinks(cleaned);
        if (directLinks.isNotEmpty) return directLinks;
        final jsonLinks = _tryExtractProxyLinksFromJson(variant);
        if (jsonLinks.isNotEmpty) return jsonLinks;
        try {
          final parsed = _parseSubscriptionContent(cleaned);
          if (parsed.isNotEmpty) return parsed;
        } on Object {}
      }
    }
    return null;
  }

  static List<String> _extractSubscriptionUrlsFromHtml(
    String html, {
    required String baseUrl,
  }) {
    final base = Uri.tryParse(baseUrl);
    if (base == null) return const [];

    final found = <String>{};
    final patterns = <RegExp>[
      RegExp(
        r'''(?:href|src|data-url)\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:fetch|axios\.get|open)\s*\(\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:window\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(html)) {
        final raw = (m.group(1) ?? '').trim();
        if (raw.isEmpty) continue;
        final resolved = base.resolve(_htmlUnescape(raw).replaceAll(r'\/', '/')).toString();
        final lower = resolved.toLowerCase();
        if (lower.endsWith('.js') ||
            lower.endsWith('.css') ||
            lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.svg') ||
            lower.contains('/login') ||
            lower.contains('/register')) {
          continue;
        }
        if (lower.contains('/sub') ||
            lower.contains('token=') ||
            lower.contains('subscription') ||
            lower.contains('/api/') ||
            lower.contains('format=')) {
          found.add(resolved);
        }
      }
    }

    return found.take(8).toList();
  }

  static Future<List<String>> _crawlHtmlForSubscriptionConfigs({
    required String html,
    required String pageUrl,
    required Duration timeout,
    required Map<String, String> hwidHeaders,
  }) async {
    final visited = <String>{pageUrl};
    var frontier = _extractSubscriptionUrlsFromHtml(html, baseUrl: pageUrl);
    const maxDepth = 2;
    const maxRequests = 12;
    var reqCount = 0;

    for (var depth = 0; depth < maxDepth && frontier.isNotEmpty; depth++) {
      final next = <String>[];
      for (final u in frontier) {
        if (reqCount >= maxRequests) break;
        if (!visited.add(u)) continue;
        if (!_isSafeUrl(u)) continue;
        reqCount++;
        try {
          final resp = await http
              .get(
                Uri.parse(u),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept': 'text/plain,*/*',
                  'Accept-Language': 'en-US,en;q=0.9',
                  'Cache-Control': 'no-cache',
                  'Pragma': 'no-cache',
                  ...hwidHeaders,
                },
              )
              .timeout(timeout);
          final body = (resp.body).trim();
          if (body.isEmpty) continue;
          if (!_looksLikeHtml(resp)) {
            try {
              final parsed = _parseSubscriptionContent(body);
              if (parsed.isNotEmpty) return parsed;
            } on Object {
              final extracted = _extractConfigsFromHtml(body);
              if (extracted != null && extracted.isNotEmpty) return extracted;
            }
          } else {
            final extracted = _extractConfigsFromHtml(body);
            if (extracted != null && extracted.isNotEmpty) return extracted;
            next.addAll(_extractSubscriptionUrlsFromHtml(body, baseUrl: u));
          }
        } on Object {
          // ignore single failure
        }
      }
      frontier = next;
    }
    return const [];
  }

  static List<String> _extractUriLinks(String text) {
    final matches = RegExp(
      r'''(?:vless|vmess|trojan|ss|hysteria|hy2)://[^\s<>"']+''',
      caseSensitive: false,
    ).allMatches(text);
    final links = <String>[];
    for (final m in matches) {
      final raw = (m.group(0) ?? '').trim();
      if (raw.isEmpty) continue;
      final normalized = raw
          .replaceAll('&amp;', '&')
          .replaceAll('&#38;', '&')
          .replaceAll('\\/', '/');
      if (_isValidServerConfig(normalized)) {
        links.add(normalized);
      }
    }
    return links.toSet().toList();
  }

  static List<String> _tryExtractProxyLinksFromJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return const [];
    }
    try {
      final decoded = jsonDecode(trimmed);
      return _extractProxyLinksFromJsonValue(decoded);
    } on Object {
      return const [];
    }
  }

  static List<String> _extractProxyLinksFromJsonValue(dynamic node) {
    final links = <String>{};
    if (node is String) {
      final directLinks = _extractUriLinks(node);
      if (directLinks.isNotEmpty) links.addAll(directLinks);
      final decoded = _tryDecodeBase64Flexible(node);
      if (decoded != null && decoded.trim().isNotEmpty) {
        links.addAll(_extractUriLinks(decoded));
      }
      return links.toList();
    }
    if (node is List) {
      for (final item in node) {
        links.addAll(_extractProxyLinksFromJsonValue(item));
      }
      return links.toList();
    }
    if (node is Map) {
      for (final value in node.values) {
        links.addAll(_extractProxyLinksFromJsonValue(value));
      }
      return links.toList();
    }
    return const [];
  }

  static bool _isValidServerConfig(String config) {
    return config.startsWith('vless://') ||
        config.startsWith('vmess://') ||
        config.startsWith('trojan://') ||
        config.startsWith('ss://') ||
        config.startsWith('hysteria://') ||
        config.startsWith('hy2://');
  }

  static bool _isMetadataConfig(String raw) {
    try {
      final uri = Uri.parse(raw);
      final host = uri.host.toLowerCase();
      if ((host == '0.0.0.0' || host == '::' || host == '::1') && uri.port <= 1) {
        return true;
      }
    } on Object {}

    final name = _extractConfigName(raw);
    if (name == null || name.isEmpty) return false;
    final n = name.toLowerCase();
    const markers = <String>[
      'пользователь',
      'осталось дней',
      'серверов доступно',
      'оплата',
      'трафик',
      'до:',
      'remaining',
      'days left',
      'expire',
      'expires',
      'traffic',
      'user:',
    ];
    for (final m in markers) {
      if (n.contains(m)) return true;
    }
    return false;
  }

  static bool _isHwidGateConfig(String raw) {
    final name = _extractConfigName(raw)?.toLowerCase() ?? '';
    if (name.isEmpty) return false;
    return name.contains('hwid') ||
        name.contains('turn on hwid') ||
        name.contains('enable hwid') ||
        name.contains('bind hwid');
  }

  static String? _extractConfigName(String raw) {
    try {
      if (raw.startsWith('vmess://')) {
        final payload = raw.substring('vmess://'.length).trim();
        final decoded = _tryDecodeBase64Flexible(payload);
        if (decoded != null) {
          final j = jsonDecode(decoded);
          if (j is Map<String, dynamic>) {
            final ps = (j['ps'] ?? '').toString().trim();
            if (ps.isNotEmpty) return ps;
          }
        }
      }
      final uri = Uri.parse(raw);
      final fragment = uri.fragment.trim();
      if (fragment.isEmpty) return null;
      return Uri.decodeComponent(fragment).trim();
    } on Object {
      return null;
    }
  }

  static String _htmlUnescape(String input) {
    var s = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    s = s.replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (m) {
      final token = m.group(1)!;
      final code = token.startsWith('x') || token.startsWith('X')
          ? int.tryParse(token.substring(1), radix: 16)
          : int.tryParse(token);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return s;
  }

  static String _jsUnescape(String input) {
    var s = input
        .replaceAll(r'\/', '/')
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
    s = s.replaceAllMapped(RegExp(r'\\u([0-9A-Fa-f]{4})'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return s;
  }

  static bool _shouldRetryWithHwidQuery(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('service links') ||
        lower.contains('no supported proxy links found') ||
        lower.contains('hwid') ||
        lower.contains('enable/bind');
  }

  static String _appendHwidQuery(String url, String hwid) {
    if (hwid.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final qp = Map<String, String>.from(uri.queryParameters);
    qp.putIfAbsent('hwid', () => hwid);
    qp.putIfAbsent('device_id', () => hwid);
    qp.putIfAbsent('deviceId', () => hwid);
    return uri.replace(queryParameters: qp).toString();
  }

  static List<String> _fallbackUrlCandidates(String url, String? hwid) {
    final out = <String>{url};
    final uri = Uri.tryParse(url);
    if (uri == null) return out.toList();

    // Trailing slash toggle
    if (!uri.path.endsWith('/')) {
      out.add(uri.replace(path: '${uri.path}/').toString());
    } else {
      final p = uri.path.substring(0, uri.path.length - 1);
      out.add(uri.replace(path: p.isEmpty ? '/' : p).toString());
    }

    // Some edge setups work only on http
    if (uri.scheme == 'https') {
      out.add(uri.replace(scheme: 'http').toString());
    } else if (uri.scheme == 'http') {
      out.add(uri.replace(scheme: 'https').toString());
    }

    if (hwid != null && hwid.isNotEmpty) {
      final withHwid = <String>{};
      for (final u in out) {
        withHwid.add(_appendHwidQuery(u, hwid));
      }
      out.addAll(withHwid);
    }

    return out.toList();
  }

  static Map<String, String> _buildHwidHeaders(AppSettings settings) {
    if (!settings.shareDeviceHwid) return const <String, String>{};
    final hwid = settings.deviceHwid.trim();
    if (hwid.isEmpty) return const <String, String>{};
    final os = Platform.operatingSystem;
    final model = Platform.localHostname;
    return {
      'x-hwid': hwid,
      'X-HWID': hwid,
      'hwid': hwid,
      'x-device-os': os,
      'X-Device-Os': os,
      'x-ver-os': Platform.operatingSystemVersion,
      'X-Ver-Os': Platform.operatingSystemVersion,
      'x-device-model': model,
      'X-Device-Model': model,
    };
  }

  static Future<UpdateResult> updateSubscriptionServers(
    Subscription subscription,
  ) async {
    try {
      final (newServers, usageInfo) = await fetchServersFromSubscription(
        subscription.url,
      );

      await UnifiedStorage.updateSubscriptionServers(
        subscriptionId: subscription.id,
        subscriptionName: subscription.name,
        newConfigs: newServers,
      );

      final updatedSubscription = subscription.copyWith(
        lastUpdated: DateTime.now(),
        serverCount: newServers.length,
        trafficUploadBytes: usageInfo.uploadBytes,
        trafficDownloadBytes: usageInfo.downloadBytes,
        trafficTotalBytes: usageInfo.totalBytes,
        expiresAt: usageInfo.expiresAt,
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

    final results = await Future.wait(
      tasks.map(
        (task) => task.catchError((e) {
          return UpdateResult(
            success: false,
            error: e.toString(),
            subscription: Subscription(
              id: 'unknown',
              name: 'unknown',
              url: '',
              lastUpdated: DateTime.now(),
            ),
          );
        }),
      ),
    );

    return results.whereType<UpdateResult>().toList();
  }

  static Future<List<UpdateResult>> updateDueSubscriptions({
    Duration interval = const Duration(hours: 12),
  }) async {
    final dueSubscriptions = await getSubscriptionsDueForUpdate(
      interval: interval,
    );
    if (dueSubscriptions.isEmpty) {
      return <UpdateResult>[];
    }

    final results = <UpdateResult>[];
    for (final subscription in dueSubscriptions) {
      results.add(await updateSubscriptionServers(subscription));
    }
    return results;
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

  static Future<void> removeSubscriptionServers(
    Subscription subscription,
  ) async {
    await UnifiedStorage.deleteSubscription(subscription.id);
  }
}
