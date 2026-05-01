import 'dart:convert';
import '../storages/improved_settings_storage.dart';
import '../core/tun_service.dart';
import '../storages/app_routing_storage.dart';

/// Updated configuration for the latest versions of Xray core and singbox core
class ConfigGeneratorV2 {
  static String generateConfig(
    String input,
    AppSettings settings, {
    VpnMode mode = VpnMode.systemProxy,
    required String adapterIp,
  }) {
    final configMap = _generateXrayConfigMap(input, settings, mode, adapterIp);
    return const JsonEncoder.withIndent('  ').convert(configMap);
  }

  static bool _isValidIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static String _decodeBase64UrlCompat(String input) {
    var normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64.decode(normalized));
  }

  static Map<String, dynamic> _parseVmessPayload(String input) {
    final payload = input.substring('vmess://'.length).trim();
    if (payload.isEmpty) {
      throw ArgumentError('VMess payload is empty');
    }

    final decoded = _decodeBase64UrlCompat(payload);
    final parsed = jsonDecode(decoded);
    if (parsed is! Map<String, dynamic>) {
      throw ArgumentError('Invalid VMess payload format');
    }
    return parsed;
  }

  /// Generate Xray-core configuration
  static Map<String, dynamic> _generateXrayConfigMap(
    String input,
    AppSettings settings,
    VpnMode mode,
    String adapterIp,
  ) {
    final trimmed = input.trim();
    final bool isVmess = trimmed.toLowerCase().startsWith('vmess://');
    final Uri uri;
    Map<String, dynamic>? vmessConfig;

    try {
      if (isVmess) {
        vmessConfig = _parseVmessPayload(trimmed);
        uri = Uri.parse('vmess://proxy');
      } else {
        uri = Uri.parse(trimmed);
      }
    } catch (e) {
      throw ArgumentError('Invalid URI format: $trimmed');
    }

    final scheme = isVmess ? 'vmess' : uri.scheme.toLowerCase();
    final address = isVmess
        ? (vmessConfig?['add']?.toString() ?? '')
        : uri.host;
    final port = isVmess
        ? int.tryParse(vmessConfig?['port']?.toString() ?? '') ?? 0
        : uri.port;

    String getParam(String key, [String def = '']) {
      if (vmessConfig != null) {
        if (key == 'type' && vmessConfig.containsKey('net')) {
          final value = vmessConfig['net'];
          return value == null ? def : value.toString();
        }
        final value = vmessConfig[key];
        if (value != null) return value.toString();
      }
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
    }

    final networkType = getParam('type', scheme == 'hysteria' ? 'quic' : 'tcp');
    final security = isVmess
        ? (vmessConfig?['tls']?.toString().toLowerCase() == 'tls' ? 'tls' : 'none')
        : getParam('security', scheme == 'trojan' ? 'tls' : (scheme == 'hysteria' ? 'none' : 'none'));
    final bool isHysteria = scheme == 'hysteria' || scheme == 'hy2';
    final sni = getParam('sni', getParam('host', address));
    final fingerprint = getParam('fp', '');
    final pinnedCert = getParam('pcs', getParam('pinnedPeerCertSha256', '')).trim();
    final verifyCertName = getParam('vcn', getParam('verifyPeerCertByName', '')).trim();

    // === Build outbound based on protocol ===
    final Map<String, dynamic> outbound;
    Map<String, dynamic> streamSettings = {'network': networkType};

    if (scheme == 'vless') {
      final uuid = uri.userInfo;
      if (uuid.isEmpty) {
        throw ArgumentError('VLESS requires UUID in userInfo');
      }

      final flow = getParam('flow');
      final encryption = getParam('encryption', 'none').trim().isEmpty
          ? 'none'
          : getParam('encryption', 'none').trim();

      outbound = {
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': {
          'address': address,
          'port': port,
          'id': uuid,
          'encryption': encryption,
          if (flow.isNotEmpty) 'flow': flow,
          'level': 0,
        },
      };
    } else if (scheme == 'trojan') {
      final password = isVmess ? (vmessConfig?['id']?.toString() ?? '') : uri.userInfo;
      if (password.isEmpty) {
        throw ArgumentError('Trojan requires password in userInfo');
      }
      final email = getParam('email');

      outbound = {
        'tag': 'proxy',
        'protocol': 'trojan',
        'settings': {
          'address': address,
          'port': port,
          'password': password,
          if (email.isNotEmpty) 'email': email,
          'level': 0,
        },
      };
    } else if (scheme == 'ss') {
      final userInfo = uri.userInfo;
      if (userInfo.isEmpty) {
        throw ArgumentError('Shadowsocks requires userInfo with method:password');
      }
      String method = '';
      String password = '';

      if (userInfo.contains(':')) {
        final splitIdx = userInfo.indexOf(':');
        method = userInfo.substring(0, splitIdx);
        password = userInfo.substring(splitIdx + 1);
      } else {
        final decoded = _decodeBase64UrlCompat(userInfo);
        final splitIdx = decoded.indexOf(':');
        if (splitIdx <= 0 || splitIdx >= decoded.length - 1) {
          throw ArgumentError('Invalid Shadowsocks userInfo format');
        }
        method = decoded.substring(0, splitIdx);
        password = decoded.substring(splitIdx + 1);
      }

      final email = getParam('email');
      final uot = getParam('uot');
      final uotVersion = getParam('UoTVersion');

      outbound = {
        'tag': 'proxy',
        'protocol': 'shadowsocks',
        'settings': {
          'address': address,
          'port': port,
          'method': method,
          'password': password,
          if (email.isNotEmpty) 'email': email,
          if (uot.isNotEmpty) 'uot': uot.toLowerCase() == 'true',
          if (uotVersion.isNotEmpty) 'UoTVersion': int.tryParse(uotVersion) ?? 0,
          'level': 0,
        },
      };
    } else if (scheme == 'vmess') {
      final uuid = vmessConfig?['id']?.toString() ?? '';
      if (uuid.isEmpty) {
        throw ArgumentError('VMess requires id in payload');
      }
      final vmessSecurityValue = vmessConfig?['security']?.toString() ?? '';
      final vmessSecurity = vmessSecurityValue.isNotEmpty ? vmessSecurityValue : 'auto';
      final flow = vmessConfig?['flow']?.toString() ?? '';

      outbound = {
        'tag': 'proxy',
        'protocol': 'vmess',
        'settings': {
          'address': address,
          'port': port,
          'id': uuid,
          'security': vmessSecurity,
          'level': 0,
          if (flow.isNotEmpty) 'flow': flow,
        },
      };
    } else if (scheme == 'hysteria' || scheme == 'hy2') {
      final auth = getParam('auth', getParam('password', '')).trim();
      if (auth.isEmpty) {
        throw ArgumentError('Hysteria requires auth/password in URI query');
      }

      final udpIdleTimeout = int.tryParse(getParam('udpIdleTimeout', '60')) ?? 60;

      Map<String, dynamic>? buildMasquerade() {
        final type = getParam('masqueradeType', getParam('masqType', ''));
        final dir = getParam('masqueradeDir', getParam('masqDir', ''));
        final url = getParam('masqueradeUrl', getParam('masqUrl', ''));
        final rewriteHost = getParam('masqueradeRewriteHost', getParam('masqRewriteHost', '')).toLowerCase() == 'true';
        final insecure = getParam('masqueradeInsecure', getParam('masqInsecure', '')).toLowerCase() == 'true';
        final content = getParam('masqueradeContent', getParam('masqContent', ''));
        final statusCode = int.tryParse(getParam('masqueradeStatusCode', getParam('masqStatusCode', '')));

        if (type.isEmpty && dir.isEmpty && url.isEmpty && content.isEmpty && !rewriteHost && !insecure && statusCode == null) {
          return null;
        }

        final map = <String, dynamic>{
          if (type.isNotEmpty) 'type': type,
          if (dir.isNotEmpty) 'dir': dir,
          if (url.isNotEmpty) 'url': url,
          if (rewriteHost) 'rewriteHost': true,
          if (insecure) 'insecure': true,
          if (content.isNotEmpty) 'content': content,
          if (statusCode != null) 'statusCode': statusCode,
        };
        return map;
      }

      final hysteriaSettings = <String, dynamic>{
        'version': int.tryParse(getParam('version', '2')) ?? 2,
        'auth': auth,
        'udpIdleTimeout': udpIdleTimeout,
        if (buildMasquerade() != null) 'masquerade': buildMasquerade(),
      };

      outbound = {
        'tag': 'proxy',
        'protocol': 'hysteria',
        'settings': {
          'address': address,
          'port': port,
          'version': hysteriaSettings['version'],
        },
      };

      streamSettings = {
        'network': networkType,
        if (security == 'tls') 'security': 'tls',
        if (security == 'reality') 'security': 'reality',
        if (security == 'tls')
          'tlsSettings': {
            'serverName': sni,
            if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
            if (pinnedCert.isNotEmpty) 'pinnedPeerCertSha256': pinnedCert,
            if (verifyCertName.isNotEmpty)
              'verifyPeerCertByName': verifyCertName
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(),
            'alpn': ['h2', 'http/1.1'],
          },
        'hysteriaSettings': hysteriaSettings,
      };

      if (networkType == 'quic') {
        streamSettings['quicSettings'] = {
          'security': getParam('quicSecurity', 'none'),
          if (getParam('key').isNotEmpty) 'key': getParam('key'),
          if (getParam('headerType').isNotEmpty)
            'header': {'type': getParam('headerType')},
        };
      }
    } else {
      throw ArgumentError('Unsupported protocol: $scheme');
    }

    // === Build stream settings ===
    if (!isHysteria) {
      if (security == 'reality') {
        final publicKey = getParam('pbk');
        if (publicKey.isEmpty) {
          throw ArgumentError('REALITY requires publicKey (pbk) in URI');
        }

        streamSettings['security'] = 'reality';
        streamSettings['realitySettings'] = {
          'show': false,
          'fingerprint': fingerprint.isNotEmpty ? fingerprint : 'chrome',
          'serverName': sni,
          'publicKey': publicKey,
          'shortId': getParam('sid', ''),
          'spiderX': getParam('spx', '/'),
        };
      } else if (security == 'tls') {
        streamSettings['security'] = 'tls';
        streamSettings['tlsSettings'] = {
          'serverName': sni,
          if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
          if (pinnedCert.isNotEmpty) 'pinnedPeerCertSha256': pinnedCert,
          if (verifyCertName.isNotEmpty)
            'verifyPeerCertByName': verifyCertName
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          'alpn': ['h2', 'http/1.1'],
        };
      }
    }

    if (networkType == 'tcp') {
      final headerType = getParam('headerType', '');
      if (headerType == 'http') {
        streamSettings['tcpSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'headers': {
                'Host': [getParam('host', address)],
                'User-Agent': [
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                ],
              },
              'method': 'GET',
              'path': [getParam('path', '/')],
            },
            'response': {'version': '1.1', 'status': '200', 'reason': 'OK'},
          },
        };
      }
    } else if (networkType == 'kcp') {
      streamSettings['kcpSettings'] = {
        if (getParam('mtu').isNotEmpty) 'mtu': int.tryParse(getParam('mtu')) ?? 1350,
        if (getParam('tti').isNotEmpty) 'tti': int.tryParse(getParam('tti')) ?? 50,
        if (getParam('uplinkCapacity').isNotEmpty)
          'uplinkCapacity': int.tryParse(getParam('uplinkCapacity')) ?? 5,
        if (getParam('downlinkCapacity').isNotEmpty)
          'downlinkCapacity': int.tryParse(getParam('downlinkCapacity')) ?? 20,
        if (getParam('congestion').isNotEmpty)
          'congestion': getParam('congestion').toLowerCase() == 'true',
        if (getParam('headerType').isNotEmpty)
          'header': {'type': getParam('headerType')},
      };
    } else if (networkType == 'quic') {
      streamSettings['quicSettings'] = {
        'security': getParam('quicSecurity', 'none'),
        if (getParam('key').isNotEmpty) 'key': getParam('key'),
        if (getParam('headerType').isNotEmpty)
          'header': {'type': getParam('headerType')},
      };
    } else if (networkType == 'ws') {
      streamSettings['wsSettings'] = {
        'path': getParam('path', '/'),
        'headers': {'Host': getParam('host', sni)},
      };
    } else if (networkType == 'grpc') {
      streamSettings['grpcSettings'] = {
        'serviceName': getParam('serviceName', ''),
        'multiMode': getParam('mode') == 'multi',
        'idleTimeout': '30s',
        'pingTimeout': '15s',
      };
    } else if (networkType == 'xhttp') {
      final xhttpSettings = <String, dynamic>{
        'path': getParam('path', '/'),
        'headers': {'Host': getParam('host', sni)},
      };
      final xhttpMode = getParam('mode', '');
      if (xhttpMode.isNotEmpty) {
        xhttpSettings['mode'] = xhttpMode;
      }
      // XHTTP requires TLS
      streamSettings['security'] = 'tls';
      streamSettings['tlsSettings'] = {
        'serverName': sni,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (pinnedCert.isNotEmpty) 'pinnedPeerCertSha256': pinnedCert,
        'alpn': ['h2'],
      };
      streamSettings['xhttpSettings'] = xhttpSettings;
    } else if (networkType == 'splithttp') {
      // SplitHTTP
      final splitHttpSettings = <String, dynamic>{
        'path': getParam('path', '/'),
        'headers': {'Host': getParam('host', sni)},
      };
      final xhttpMode = getParam('mode', '');
      if (xhttpMode.isNotEmpty) {
        splitHttpSettings['mode'] = xhttpMode;
      }
      streamSettings['security'] = 'tls';
      streamSettings['tlsSettings'] = {
        'serverName': sni,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (pinnedCert.isNotEmpty) 'pinnedPeerCertSha256': pinnedCert,
        'alpn': ['h2'],
      };
      streamSettings['splitHttpSettings'] = splitHttpSettings;
    } else if (networkType == 'httpupgrade') {
      streamSettings['httpupgradeSettings'] = {
        'path': getParam('path', '/'),
        'host': getParam('host', sni),
      };
    }

    outbound['streamSettings'] = streamSettings;

    if (mode == VpnMode.tun && adapterIp.isNotEmpty) {
      outbound['sendThrough'] = adapterIp;
    }

    List<String> parseList(String s) =>
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final customDnsEntries = parseList(settings.customDnsServers);
    final xrayDnsServers = (settings.useCustomDns && customDnsEntries.isNotEmpty)
        ? customDnsEntries
        : <String>['8.8.8.8', '1.1.1.1'];

    List<String> normalizeDomains(List<String> domains) {
      return domains.map((domain) {
        final cleaned = domain.trim().toLowerCase();
        if (cleaned.isEmpty) return '';
        if (cleaned.startsWith('domain:') ||
            cleaned.startsWith('full:') ||
            cleaned.startsWith('regexp:') ||
            cleaned.startsWith('geosite:')) {
          return cleaned;
        }
        if (!cleaned.contains('.')) {
          // Treat short values like "ru" as TLD/domain suffix, not "match everything".
          final escaped = cleaned.replaceAllMapped(
            RegExp(r'[\\^$.|?*+(){}\[\]-]'),
            (m) => '\\${m.group(0)}',
          );
          return 'regexp:(^|\\.)$escaped\$';
        }
        if (cleaned.startsWith('.')) {
          return 'domain:${cleaned.substring(1)}';
        }
        return 'domain:$cleaned';
      }).where((e) => e.isNotEmpty).toList();
    }

    final rules = <Map<String, dynamic>>[];

    // Block reserved IPs
    rules.add({
      'ip': ['169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32'],
      'outboundTag': 'block',
    });

    // Blocked domains
    final blockedDomains = normalizeDomains(parseList(settings.blockedDomains));
    if (blockedDomains.isNotEmpty) {
      rules.add({'domain': blockedDomains, 'outboundTag': 'block'});
    }

    // Direct route for server address in proxy mode
    if (mode == VpnMode.systemProxy) {
      if (_isValidIPv4(address)) {
        rules.add({'ip': [address], 'outboundTag': 'direct'});
      } else {
        rules.add({'domain': ['full:$address'], 'outboundTag': 'direct'});
      }
    }

    // User-defined direct domains and IPs
    final directDomains = normalizeDomains(parseList(settings.directDomains));
    if (directDomains.isNotEmpty) {
      rules.add({'domain': directDomains, 'outboundTag': 'direct'});
    }

    final directIps = parseList(settings.directIps);
    if (directIps.isNotEmpty) {
      rules.add({'ip': directIps, 'outboundTag': 'direct'});
    }

    // Route private IPs direct
    rules.add({'ip': ['geoip:private'], 'outboundTag': 'direct'});

    // User-defined proxy domains
    final proxyDomains = normalizeDomains(parseList(settings.proxyDomains));
    if (proxyDomains.isNotEmpty) {
      rules.add({'domain': proxyDomains, 'outboundTag': 'proxy'});
    }

    // Default: route all other traffic through proxy
    rules.add({'outboundTag': 'proxy', 'network': 'tcp,udp'});

    // === Build outbounds array ===
    final outbounds = <Map<String, dynamic>>[
      outbound,
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {'response': {'type': 'http'}}},
    ];

    final sniffing = {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': false,
    };

    final inbounds = <Map<String, dynamic>>[];

    if (mode == VpnMode.tun) {
      inbounds.add({
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': settings.localPort,
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': sniffing,
      });
    } else {
      inbounds.add({
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'port': settings.localPort,
        'protocol': 'mixed',
        'settings': {
          'auth': 'noauth',
          'udp': true,
          'allowTransparent': true,
        },
        'sniffing': sniffing,
      });
    }

    final config = <String, dynamic>{
      'log': {
        'loglevel': 'warning',
        'access': '',
        'error': '',
      },
      'dns': {
        'servers': xrayDnsServers,
        'queryStrategy': 'UseIPv4',
      },
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'domainMatcher': 'linear',
        'rules': rules,
      },
      'inbounds': inbounds,
      'outbounds': outbounds,
    };

    // перезаписываем inbounds для socks
    if (mode == VpnMode.tun) {
      config['inbounds'] = [
        {
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'port': settings.localPort,
          'protocol': 'socks',
          'settings': {'auth': 'noauth', 'udp': true},
          'sniffing': sniffing,
        },
      ];
    }



    return config;
  }
}

/// Updated for sing-box 1.13+
class SingBoxChainGen {
  static String generateTunConfig({
    required int localSocksPort,
    required String serverIpToExclude,
    required AppSettings settings,
    List<String> vpnProcessNames = const [],
    AppRoutingMode routingMode = AppRoutingMode.allProxy,
  }) {
    List<String> parseList(String s) =>
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    Map<String, dynamic> buildProxyDnsServer() {
      final customDns = parseList(settings.customDnsServers);
      final first = (settings.useCustomDns && customDns.isNotEmpty)
          ? customDns.first
          : '1.1.1.1';
      final raw = first.trim();
      final lower = raw.toLowerCase();

      if (lower.startsWith('https://') || lower.startsWith('http://')) {
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.host.isNotEmpty) {
          return {
            'tag': 'proxy-dns',
            'type': 'https',
            'server': uri.host,
            if (uri.hasPort) 'server_port': uri.port,
            if (uri.path.isNotEmpty && uri.path != '/') 'path': uri.path,
            'detour': 'proxy',
          };
        }
      }

      String host = raw;
      int? port;
      if (raw.contains(':') && !raw.contains('://')) {
        final idx = raw.lastIndexOf(':');
        final p = int.tryParse(raw.substring(idx + 1));
        if (p != null) {
          host = raw.substring(0, idx).trim();
          port = p;
        }
      }

      return {
        'tag': 'proxy-dns',
        'type': 'udp',
        'server': host,
        if (port != null) 'server_port': port,
        'detour': 'proxy',
      };
    }

    ({
      List<String> domain,
      List<String> domainSuffix,
      List<String> domainRegex,
    }) classifyDomains(List<String> domains) {
      final exact = <String>[];
      final suffix = <String>[];
      final regex = <String>[];

      for (final raw in domains) {
        final cleaned = raw.trim().toLowerCase();
        if (cleaned.isEmpty) continue;

        if (cleaned.startsWith('full:')) {
          final v = cleaned.substring('full:'.length).trim();
          if (v.isNotEmpty) exact.add(v);
          continue;
        }

        if (cleaned.startsWith('regexp:')) {
          final v = cleaned.substring('regexp:'.length).trim();
          if (v.isNotEmpty) regex.add(v);
          continue;
        }

        if (cleaned.startsWith('domain:')) {
          final v = cleaned.substring('domain:'.length).trim();
          if (v.isNotEmpty) suffix.add(v.startsWith('.') ? v.substring(1) : v);
          continue;
        }

        if (cleaned.startsWith('geosite:')) {
          // sing-box route no longer supports geosite directly
          final v = cleaned.substring('geosite:'.length).trim();
          if (v.isNotEmpty) suffix.add(v);
          continue;
        }

        if (cleaned.startsWith('.')) {
          final v = cleaned.substring(1).trim();
          if (v.isNotEmpty) suffix.add(v);
          continue;
        }

        if (!cleaned.contains('.')) {
          suffix.add(cleaned);
          continue;
        }

        suffix.add(cleaned);
      }

      return (domain: exact, domainSuffix: suffix, domainRegex: regex);
    }

    void addDomainRule({
      required List<Map<String, dynamic>> targetRules,
      required List<String> sourceDomains,
      required String outbound,
      required String action,
    }) {
      final parts = classifyDomains(sourceDomains);
      if (parts.domain.isEmpty &&
          parts.domainSuffix.isEmpty &&
          parts.domainRegex.isEmpty) {
        return;
      }
      targetRules.add({
        if (parts.domain.isNotEmpty) 'domain': parts.domain,
        if (parts.domainSuffix.isNotEmpty) 'domain_suffix': parts.domainSuffix,
        if (parts.domainRegex.isNotEmpty) 'domain_regex': parts.domainRegex,
        'outbound': outbound,
        'action': action,
      });
    }

    final directDomains = parseList(settings.directDomains);
    final blockedDomains = parseList(settings.blockedDomains);
    final proxyDomains = parseList(settings.proxyDomains);
    final directIps = parseList(settings.directIps);

    bool isIPv4OrCidr(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      final ipV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
      final cidrV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$');
      return ipV4.hasMatch(v) || cidrV4.hasMatch(v);
    }

    bool isIPv6OrCidr(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      final ipV6 = RegExp(r'^[0-9a-fA-F:]+$');
      final cidrV6 = RegExp(r'^[0-9a-fA-F:]+/\d{1,3}$');
      return ipV6.hasMatch(v) || cidrV6.hasMatch(v);
    }

    final directIpsForSingBox = directIps
        .where((entry) =>
            isIPv4OrCidr(entry) ||
            isIPv6OrCidr(entry) ||
            entry.trim().toLowerCase() == 'geoip:private')
        .map((e) => e.trim())
        .toList();


    final rules = <Map<String, dynamic>>[];

    // Hijack DNS packets from TUN to sing-box DNS module to avoid DNS loops.
    rules.add({
      'port': 53,
      'action': 'hijack-dns',
    });

    // Process-based routing
    if (vpnProcessNames.isNotEmpty) {
      switch (routingMode) {
        case AppRoutingMode.onlySelected:
          rules.add({
            'process_name': vpnProcessNames,
            'outbound': 'proxy',
            'action': 'route',
          });
          break;
        case AppRoutingMode.allExceptSelected:
          rules.add({
            'process_name': vpnProcessNames,
            'outbound': 'direct',
            'action': 'route',
          });
          break;
        case AppRoutingMode.allProxy:
          break;
      }
    }

    // Blocked domains
    if (blockedDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: blockedDomains,
        outbound: 'block',
        action: 'route',
      );
    }

    final serverExcludeCidrs = <String>[];
    if (serverIpToExclude.isNotEmpty) {
      if (serverIpToExclude.contains('/')) {
        serverExcludeCidrs.add(serverIpToExclude);
      } else {
        serverExcludeCidrs.add('$serverIpToExclude/32');
      }
    }

    // Exclude server IP from tunnel
    if (serverExcludeCidrs.isNotEmpty) {
      rules.add({
        'ip_cidr': serverExcludeCidrs,
        'outbound': 'direct',
        'action': 'route',
      });
    }

    // Direct domains
    if (directDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: directDomains,
        outbound: 'direct',
        action: 'route',
      );
    }

    // Direct IPs
    if (directIpsForSingBox.isNotEmpty) {
      rules.add({
        'ip_cidr': directIpsForSingBox,
        'outbound': 'direct',
        'action': 'route',
      });
    }

    // Private IPs
    rules.add({
      'ip_cidr': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8'],
      'outbound': 'direct',
      'action': 'route',
    });

    // Proxy domains
    if (proxyDomains.isNotEmpty) {
      addDomainRule(
        targetRules: rules,
        sourceDomains: proxyDomains,
        outbound: 'proxy',
        action: 'route',
      );
    }

    final routeFinal = (routingMode == AppRoutingMode.onlySelected) ? 'direct' : 'proxy';
    
    final map = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
        'output': 'stdout',
      },
      'dns': {
        'servers': [
          buildProxyDnsServer(),
          {
            'tag': 'local-dns',
            'type': 'local',
          },
        ],
        'strategy': 'ipv4_only',
        'final': 'proxy-dns',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'tun-keqdis',
          'mtu': 1500,
          'address': ['172.19.0.1/30', 'fd00::1/126'],
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'sniff': true,
          'sniff_override_destination': true,
        },
      ],
      'outbounds': [
        {
          'type': 'socks',
          'tag': 'proxy',
          'server': '127.0.0.1',
          'server_port': localSocksPort,
          'version': '5',
          'udp_over_tcp': false,
        },
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
      'route': {
        'auto_detect_interface': true,
        'find_process': true,
        'default_domain_resolver': 'proxy-dns',
        'rules': rules,
        'final': routeFinal,
      },
    };


    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static String generateSocksConfig({
    required int localPort,
    required String serverAddress,
    required int serverPort,
    required String protocol,
    Map<String, dynamic>? protocolSettings,
  }) {
    final outbounds = <Map<String, dynamic>>[
      {
        'type': protocol,
        'tag': 'proxy',
        'server': serverAddress,
        'server_port': serverPort,
        if (protocolSettings != null) ...protocolSettings,
      },
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
    ];

    final map = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'inbounds': [
        {
          'type': 'socks',
          'tag': 'socks-in',
          'listen': '127.0.0.1',
          'listen_port': localPort,
          'auth': 'noauth',
          'udp': true,
        },
      ],
      'outbounds': outbounds,
      'route': {
        'auto_detect_interface': true,
        'rules': [
          {
            'action': 'route',
            'outbound': 'proxy',
          },
        ],
        'final': 'proxy',
      },
    };


    return const JsonEncoder.withIndent('  ').convert(map);
  }
}