import 'dart:convert';
import '../storages/improved_settings_storage.dart';
import '../core/tun_service.dart';

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

  static Map<String, dynamic> _generateConfigMap(
      String input,
      AppSettings settings,
      VpnMode mode,
      String adapterIp,
      ) {
    final trimmed = input.trim();
    final uri = Uri.parse(trimmed);
    final uuid = uri.userInfo;
    final address = uri.host;
    final port = uri.port;

    String getParam(String key, [String def = '']) {
      final val = uri.queryParametersAll[key];
      return (val != null && val.isNotEmpty) ? val.first : def;
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
              {"id": uuid, "encryption": "none", "flow": getParam('flow')}
            ]
          }
        ]
      },
      "streamSettings": <String, dynamic>{
        "network": getParam('type', 'tcp'),
        "security": getParam('security', 'none'),
      }
    };

    if (mode == VpnMode.tun && adapterIp.isNotEmpty) {
      outbound['sendThrough'] = adapterIp;
      (outbound['streamSettings'] as Map)['sockopt'] = {"tcpFastOpen": true};
    }

    // Transport Settings
    final stream = outbound['streamSettings'] as Map<String, dynamic>;
    final type = stream['network'];
    final security = stream['security'];
    final sni = getParam('sni', getParam('host', address));

    if (security == 'tls') {
      stream['tlsSettings'] = {
        "serverName": sni,
        "allowInsecure": false,
        "fingerprint": getParam('fp', '')
      };
    } else if (security == 'reality') {
      stream['realitySettings'] = {
        "show": false,
        "fingerprint": getParam('fp', 'chrome'),
        "serverName": sni,
        "publicKey": getParam('pbk'),
        "shortId": getParam('sid'),
        "spiderX": getParam('spx')
      };
    }

    if (type == 'tcp' && getParam('headerType') == 'http') {
      stream['tcpSettings'] = {
        "header": {
          "type": "http",
          "request": {
            "headers": {"Host": [getParam('host', address)]}
          }
        }
      };
    } else if (type == 'ws') {
      stream['wsSettings'] = {
        "path": getParam('path', '/'),
        "headers": {"Host": getParam('host', sni)}
      };
    } else if (type == 'grpc') {
      stream['grpcSettings'] = {
        "serviceName": getParam('serviceName'),
        "multiMode": getParam('mode') == 'multi'
      };
    } else if (type == 'xhttp' || type == 'splithttp') {
      final xhttpSettings = <String, dynamic>{
        "path": getParam('path', '/'),
      };

      final host = getParam('host');
      xhttpSettings['host'] = host.isNotEmpty ? host : sni;

      final xhttpMode = getParam('mode');
      if (xhttpMode.isNotEmpty) {
        xhttpSettings['mode'] = xhttpMode;
      }

      stream['xhttpSettings'] = xhttpSettings;
    } else if (type == 'httpupgrade') {
      stream['httpupgradeSettings'] = {
        "path": getParam('path', '/'),
        "host": getParam('host', sni),
      };
    }


    List<String> _parseList(String input) {
      return input
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<String> _normalizeDomains(List<String> domains) {
      return domains.map((domain) {
        final cleaned = domain.trim().toLowerCase();

        if (cleaned.startsWith('domain:') ||
            cleaned.startsWith('full:') ||
            cleaned.startsWith('regexp:') ||
            cleaned.startsWith('geosite:')) {
          return cleaned;
        }

        if (!cleaned.contains('.')) {
          return 'regexp:.*\\.${cleaned}\$';
        }

        if (cleaned.startsWith('.')) {
          return 'domain:${cleaned.substring(1)}';
        }

        return 'domain:$cleaned';
      }).toList();
    }

    final directDomains = _normalizeDomains(_parseList(settings.directDomains));
    final blockedDomains = _normalizeDomains(_parseList(settings.blockedDomains));
    final proxyDomains = _normalizeDomains(_parseList(settings.proxyDomains));
    final directIps = _parseList(settings.directIps);

    final rules = <Map<String, dynamic>>[];

    rules.add({
      "type": "field",
      "ip": ["169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"],
      "outboundTag": "block"
    });

    if (blockedDomains.isNotEmpty) {
      rules.add({
        "type": "field",
        "domain": blockedDomains,
        "outboundTag": "block"
      });
    }

    if (mode == VpnMode.systemProxy) {
      final isIpAddress = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(address);
      if (isIpAddress) {
        rules.add({
          "type": "field",
          "ip": [address],
          "outboundTag": "direct"
        });
      } else {
        rules.add({
          "type": "field",
          "domain": [address],
          "outboundTag": "direct"
        });
      }
    }

    if (directDomains.isNotEmpty) {
      rules.add({
        "type": "field",
        "domain": directDomains,
        "outboundTag": "direct"
      });
    }

    if (directIps.isNotEmpty) {
      rules.add({
        "type": "field",
        "ip": directIps,
        "outboundTag": "direct"
      });
    }

    rules.add({
      "type": "field",
      "ip": ["geoip:private"],
      "outboundTag": "direct"
    });

    if (mode == VpnMode.systemProxy) {
      rules.add({
        "type": "field",
        "port": "53",
        "network": "udp",
        "outboundTag": "dns-out"
      });
    }

    if (proxyDomains.isNotEmpty) {
      rules.add({
        "type": "field",
        "domain": proxyDomains,
        "outboundTag": "proxy"
      });
    }

    rules.add({
      "type": "field",
      "outboundTag": "proxy",
      "network": "tcp,udp"
    });

    // --- CONFIG ---
    final config = <String, dynamic>{
      "log": {"loglevel": "info"},
      "inbounds": <Map<String, dynamic>>[],
      "outbounds": <Map<String, dynamic>>[
        outbound,
        <String, dynamic>{"protocol": "freedom", "tag": "direct"},
        <String, dynamic>{"protocol": "blackhole", "tag": "block"}
      ],
      "routing": {
        "domainStrategy": "AsIs",
        "rules": rules
      }
    };

    if (mode == VpnMode.systemProxy) {
      config["dns"] = {
        "servers": ["fakedns", "8.8.8.8", "1.1.1.1"],
        "tag": "dns-out",
        "queryStrategy": "UseIPv4"
      };
      config["fakedns"] = [{"ipPool": "198.18.0.0/15", "poolSize": 65535}];
      config["outbounds"].add(<String, dynamic>{"protocol": "dns", "tag": "dns-out"});
    }


    if (mode == VpnMode.tun) {
      config['inbounds'].add({
        "tag": "socks-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {
          "auth": "noauth",
          "udp": true,
          "ip": "127.0.0.1"
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic"]
        }
      });
    } else {
      config['inbounds'].add({
        "tag": "mixed-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "mixed",
        "settings": {
          "allowTransparent": false,
          "udpEnabled": true
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic"]
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
  }) {
    List<String> _parseList(String input) {
      return input
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<String> _normalizeDomains(List<String> domains) {
      return domains.map((domain) {
        final cleaned = domain.trim().toLowerCase();

        if (cleaned.startsWith('.')) {
          return cleaned.substring(1);
        }

        return cleaned;
      }).toList();
    }

    final directDomains = _normalizeDomains(_parseList(settings.directDomains));
    final blockedDomains = _normalizeDomains(_parseList(settings.blockedDomains));
    final proxyDomains = _normalizeDomains(_parseList(settings.proxyDomains));
    final directIps = _parseList(settings.directIps);

    // --- ROUTING RULES ---
    final rules = <Map<String, dynamic>>[];

    rules.add({
      "protocol": ["dns"],
      "action": "hijack-dns"
    });

    if (blockedDomains.isNotEmpty) {
      rules.add({
        "domain": blockedDomains,
        "outbound": "block"
      });
    }

    if (serverIpToExclude.isNotEmpty) {
      rules.add({
        "ip_cidr": [serverIpToExclude],
        "outbound": "direct"
      });
    }

    if (directDomains.isNotEmpty) {
      rules.add({
        "domain_suffix": directDomains,
        "outbound": "direct"
      });
    }

    if (directIps.isNotEmpty) {
      rules.add({
        "ip_cidr": directIps,
        "outbound": "direct"
      });
    }

    rules.add({
      "ip_is_private": true,
      "outbound": "direct"
    });

    if (proxyDomains.isNotEmpty) {
      rules.add({
        "domain_suffix": proxyDomains,
        "outbound": "proxy-out"
      });
    }

    rules.add({
      "outbound": "proxy-out"
    });

    final dnsRules = <Map<String, dynamic>>[];

    if (directDomains.isNotEmpty) {
      dnsRules.add({
        "domain_suffix": directDomains,
        "server": "local-dns"
      });
    }

    dnsRules.add({
      "server": "google-dns"
    });

    final map = {
      "log": {
        "level": "info",
        "timestamp": true
      },
      "dns": {
        "servers": [
          {
            "tag": "google-dns",
            "address": "udp://1.1.1.1",
            "detour": "proxy-out"
          },
          {
            "tag": "local-dns",
            "address": "local",
            "detour": "direct"
          }
        ],
        "rules": dnsRules,
        "strategy": "ipv4_only"
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
          "sniff": true,
          "sniff_override_destination": false
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
          "tag": "direct"
        },
        {
          "type": "block",
          "tag": "block"
        }
      ],
      "route": {
        "auto_detect_interface": true,
        "rules": rules
      }
    };

    return const JsonEncoder.withIndent('  ').convert(map);
  }
}