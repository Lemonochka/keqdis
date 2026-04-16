import 'dart:convert';
import '../storages/improved_settings_storage.dart';
import '../core/tun_service.dart';
import '../storages/app_routing_storage.dart';

class ConfigGeneratorV2 {

  static String generateConfig(
      String input,
      AppSettings settings, {
        VpnMode mode = VpnMode.systemProxy,
        required String adapterIp,
      }) {
    final configMap = _generateConfigMap(input, settings, mode, adapterIp);
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

  static Map<String, dynamic> _generateConfigMap(
      String input,
      AppSettings settings,
      VpnMode mode,
      String adapterIp,
      ) {
    final trimmed = input.trim();

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      throw ArgumentError('Невалидный URI: $e');
    }

    final uuid = uri.userInfo;
    final address = uri.host;
    final port = uri.port;

    if (uuid.isEmpty) {
      throw ArgumentError('UUID (userInfo) отсутствует в URI. Проверьте формат ссылки.');
    }

    String getParam(String key, [String def = '']) {
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
    }

    final flow = getParam('flow');
    final networkType = getParam('type', 'tcp');
    final security = getParam('security', 'none');
    final vlessEncryption = (() {
      final enc = getParam('encryption', 'none').trim();
      return enc.isEmpty ? 'none' : enc;
    })();

    if (flow == 'xtls-rprx-vision' && networkType != 'tcp' && networkType != 'xhttp') {
      throw ArgumentError(
          'Flow "xtls-rprx-vision" совместим только с транспортом tcp или xhttp, '
              'но указан "$networkType"'
      );
    }

    final outbound = <String, dynamic>{
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": address,
            "port": port,
            "users": [
              {"id": uuid, "encryption": vlessEncryption, "flow": flow}
            ]
          }
        ]
      },
      "streamSettings": <String, dynamic>{
        "network": networkType,
        "security": security,
      }
    };

    if (mode == VpnMode.tun && adapterIp.isNotEmpty) {
      outbound['sendThrough'] = adapterIp;
      (outbound['streamSettings'] as Map<String, dynamic>)['sockopt'] = {"tcpFastOpen": true};
    }

    final stream = outbound['streamSettings'] as Map<String, dynamic>;
    final sni = getParam('sni', getParam('host', address));

    if (security == 'tls') {
      // Xray-core v26.2.6+ removed "allowInsecure".
      // Use:
      // - pinnedPeerCertSha256 (share param: pcs)
      // - verifyPeerCertByName (share param: vcn)
      final allowInsecureRaw = getParam('allowInsecure', '').trim();
      final allowInsecure = allowInsecureRaw == '1' ||
          allowInsecureRaw.toLowerCase() == 'true' ||
          allowInsecureRaw.toLowerCase() == 'yes';

      final pcs = getParam('pcs', getParam('pinnedPeerCertSha256', '')).trim();
      final vcnRaw = getParam('vcn', getParam('verifyPeerCertByName', '')).trim();

      if (allowInsecure && pcs.isEmpty) {
        throw ArgumentError(
          'Параметр allowInsecure устарел/удалён в Xray-core (2026). '
          'Обновите ссылку/подписку и используйте pcs (pinnedPeerCertSha256) '
          'и при необходимости vcn (verifyPeerCertByName).',
        );
      }

      stream['tlsSettings'] = {
        "serverName": sni,
        if (getParam('fp', '').isNotEmpty) "fingerprint": getParam('fp', ''),
        if (pcs.isNotEmpty) "pinnedPeerCertSha256": pcs,
        if (vcnRaw.isNotEmpty)
          "verifyPeerCertByName": vcnRaw
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
      };
    } else if (security == 'reality') {
      final publicKey = getParam('pbk');
      final shortId = getParam('sid');

      if (publicKey.isEmpty) {
        throw ArgumentError('REALITY требует параметр publicKey (pbk) в URI');
      }

      stream['realitySettings'] = {
        "show": false,
        "fingerprint": getParam('fp', 'chrome'),
        "serverName": sni,
        "publicKey": publicKey,
        "shortId": shortId,
        "spiderX": getParam('spx')
      };
    }

    if (networkType == 'tcp' && getParam('headerType') == 'http') {
      stream['tcpSettings'] = {
        "header": {
          "type": "http",
          "request": {"headers": {"Host": [getParam('host', address)]}}
        }
      };
    } else if (networkType == 'ws') {
      stream['wsSettings'] = {
        "path": getParam('path', '/'),
        "headers": {"Host": getParam('host', sni)}
      };
    } else if (networkType == 'grpc') {
      stream['grpcSettings'] = {
        "serviceName": getParam('serviceName'),
        "multiMode": getParam('mode') == 'multi'
      };
    } else if (networkType == 'xhttp' || networkType == 'splithttp') {
      final xhttpSettings = <String, dynamic>{"path": getParam('path', '/')};
      final host = getParam('host');
      xhttpSettings['host'] = host.isNotEmpty ? host : sni;
      final xhttpMode = getParam('mode');
      if (xhttpMode.isNotEmpty) xhttpSettings['mode'] = xhttpMode;
      stream['xhttpSettings'] = xhttpSettings;
    } else if (networkType == 'httpupgrade') {
      stream['httpupgradeSettings'] = {
        "path": getParam('path', '/'),
        "host": getParam('host', sni),
      };
    }

    List<String> parseList(String s) =>
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    List<String> normalizeDomains(List<String> domains) {
      return domains.map((domain) {
        final cleaned = domain.trim().toLowerCase();
        if (cleaned.startsWith('domain:') ||
            cleaned.startsWith('full:') ||
            cleaned.startsWith('regexp:') ||
            cleaned.startsWith('geosite:')) {
          return cleaned;
        }
        if (!cleaned.contains('.')) {
          return 'regexp:.*\\.$cleaned\$';
        }
        if (cleaned.startsWith('.')) {
          return 'domain:${cleaned.substring(1)}';
        }
        return 'domain:$cleaned';
      }).toList();
    }

    final directDomains = normalizeDomains(parseList(settings.directDomains));
    final blockedDomains = normalizeDomains(parseList(settings.blockedDomains));
    final proxyDomains = normalizeDomains(parseList(settings.proxyDomains));
    final directIps = parseList(settings.directIps);

    final rules = <Map<String, dynamic>>[];

    if (mode == VpnMode.systemProxy) {
      rules.add({
        "type": "field",
        "port": "53",
        "network": "udp",
        "outboundTag": "dns-out"
      });
    }

    rules.add({
      "type": "field",
      "ip": ["169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"],
      "outboundTag": "block"
    });

    if (blockedDomains.isNotEmpty) {
      rules.add({"type": "field", "domain": blockedDomains, "outboundTag": "block"});
    }

    if (mode == VpnMode.systemProxy) {
      if (_isValidIPv4(address)) {
        rules.add({"type": "field", "ip": [address], "outboundTag": "direct"});
      } else {
        rules.add({"type": "field", "domain": ["full:$address"], "outboundTag": "direct"});
      }
    }

    if (directDomains.isNotEmpty) {
      rules.add({"type": "field", "domain": directDomains, "outboundTag": "direct"});
    }
    if (directIps.isNotEmpty) {
      rules.add({"type": "field", "ip": directIps, "outboundTag": "direct"});
    }

    rules.add({"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"});

    if (proxyDomains.isNotEmpty) {
      rules.add({"type": "field", "domain": proxyDomains, "outboundTag": "proxy"});
    }

    rules.add({"type": "field", "outboundTag": "proxy", "network": "tcp,udp"});

    final outbounds = <Map<String, dynamic>>[
      outbound,
      {"protocol": "freedom", "tag": "direct"},
      {"protocol": "blackhole", "tag": "block"}
    ];

    final config = <String, dynamic>{
      "log": {"loglevel": "warning"},
      "inbounds": <Map<String, dynamic>>[],
      "outbounds": outbounds,
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": rules
      }
    };

    if (mode == VpnMode.systemProxy) {
      config["dns"] = {
        "servers": ["fakedns", "8.8.8.8", "1.1.1.1"],
        "queryStrategy": "UseIPv4"
      };
      config["fakedns"] = [{"ipPool": "198.18.0.0/15", "poolSize": 65535}];
      outbounds.add({"protocol": "dns", "tag": "dns-out"});
    }

    if (mode == VpnMode.tun) {
      config["dns"] = {
        "servers": [
          "8.8.8.8",
          "1.1.1.1",
        ],
        "queryStrategy": "UseIPv4"
      };
    }

    if (mode == VpnMode.tun) {
      config['inbounds'].add({
        "tag": "socks-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": true, "ip": "127.0.0.1"},
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic", "fakedns"],
          "routeOnly": true
        }
      });
    } else {
      config['inbounds'].add({
        "tag": "mixed-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": true},
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic", "fakedns"],
          "routeOnly": true
        }
      });
    }

    return config;
  }
}


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

    List<String> normalizeDomains(List<String> domains) {
      return domains.map((domain) {
        var cleaned = domain.trim().toLowerCase();
        for (final prefix in ['domain:', 'full:', 'regexp:', 'geosite:']) {
          if (cleaned.startsWith(prefix)) {
            cleaned = cleaned.substring(prefix.length);
            break;
          }
        }
        if (cleaned.startsWith('.')) cleaned = cleaned.substring(1);
        cleaned = cleaned.trim();
        if (cleaned.isEmpty) return '';
        return cleaned;
      }).where((d) => d.isNotEmpty).toList();
    }

    final directDomains = normalizeDomains(parseList(settings.directDomains));
    final blockedDomains = normalizeDomains(parseList(settings.blockedDomains));
    final proxyDomains = normalizeDomains(parseList(settings.proxyDomains));
    final directIps = parseList(settings.directIps);

    final rules = <Map<String, dynamic>>[];

    rules.add({"action": "sniff"});

    rules.add({"action": "hijack-dns", "protocol": ["dns"]});

    if (vpnProcessNames.isNotEmpty) {
      switch (routingMode) {
        case AppRoutingMode.onlySelected:
          rules.add({
            "action": "route",
            "outbound": "proxy-out",
            "process_name": vpnProcessNames,
          });
        case AppRoutingMode.allExceptSelected:
          rules.add({
            "action": "route",
            "outbound": "direct",
            "process_name": vpnProcessNames,
          });
        case AppRoutingMode.allProxy:
          break;
      }
    }

    if (blockedDomains.isNotEmpty) {
      rules.add({"action": "reject", "domain_suffix": blockedDomains});
    }

    if (serverIpToExclude.isNotEmpty) {
      rules.add({
        "action": "route",
        "outbound": "direct",
        "ip_cidr": ["$serverIpToExclude/32"],
      });
    }


    if (directDomains.isNotEmpty) {
      rules.add({
        "action": "route",
        "outbound": "direct",
        "domain_suffix": directDomains,
      });
    }

    if (directIps.isNotEmpty) {
      rules.add({
        "action": "route",
        "outbound": "direct",
        "ip_cidr": directIps,
      });
    }

    rules.add({"action": "route", "outbound": "direct", "ip_is_private": true});

    if (proxyDomains.isNotEmpty) {
      rules.add({
        "action": "route",
        "outbound": "proxy-out",
        "domain_suffix": proxyDomains,
      });
    }

    final dnsRules = <Map<String, dynamic>>[];

    if (vpnProcessNames.isNotEmpty && routingMode == AppRoutingMode.onlySelected) {
      dnsRules.add({
        "action": "route",
        "process_name": vpnProcessNames,
        "server": "remote-dns"
      });
    }

    if (directDomains.isNotEmpty) {
      dnsRules.add({
        "action": "route",
        "domain_suffix": directDomains,
        "server": "local-dns"
      });
    }

    final dnsFinal = (routingMode == AppRoutingMode.onlySelected)
        ? "local-dns"
        : "remote-dns";

    final routeFinal = (routingMode == AppRoutingMode.onlySelected)
        ? "direct"
        : "proxy-out";

    final map = <String, dynamic>{
      "log": {"level": "info", "timestamp": true},
      "dns": {
        "servers": [
          {
            "type": "udp",
            "tag": "remote-dns",
            "server": "1.1.1.1",
            "server_port": 53,
            "detour": "proxy-out"
          },
          {
            "type": "local",
            "tag": "local-dns",
            "detour": "direct"
          }
        ],
        "rules": dnsRules,
        "strategy": "ipv4_only",
        "final": dnsFinal
      },
      "inbounds": [
        {
          "type": "tun",
          "tag": "tun-in",
          "interface_name": "tun-keqdis",
          "address": ["172.19.0.1/30"],
          "mtu": 1400,
          "auto_route": true,
          "strict_route": true,
          "stack": "mixed",
          "endpoint_independent_nat": true,
        }
      ],
      "outbounds": [
        {
          "type": "socks",
          "tag": "proxy-out",
          "server": "127.0.0.1",
          "server_port": localSocksPort,
          "version": "5",
          "udp_over_tcp": false
        },
        {
          "type": "direct",
          "tag": "direct",
          "domain_resolver": "local-dns"
        },
      ],
      "route": {
        "auto_detect_interface": true,
        "find_process": true,
        "final": routeFinal,
        "default_domain_resolver": "remote-dns",
        "rules": rules
      }
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
