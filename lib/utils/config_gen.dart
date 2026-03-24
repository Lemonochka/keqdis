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
        "address": address,
        "port": port,
        "id": uuid,
        "flow": getParam('flow'),
        "encryption": getParam('encryption', 'none')
      },
      "streamSettings": <String, dynamic>{
        "network": getParam('type', 'raw'),
        "security": getParam('security', 'none'),
      }
    };

    if (mode == VpnMode.tun && adapterIp.isNotEmpty) {
      outbound['sendThrough'] = adapterIp;
      (outbound['streamSettings'] as Map)['sockopt'] = {"tcpFastOpen": true};
    }

    final stream = outbound['streamSettings'] as Map<String, dynamic>;
    final type = stream['network'];
    final security = stream['security'];
    final sni = getParam('sni', getParam('host', address));

    if (security == 'tls') {
      stream['tlsSettings'] = {
        "serverName": sni,
        "fingerprint": getParam('fp', '')
      };
    } else if (security == 'reality') {
      stream['realitySettings'] = {
        "fingerprint": getParam('fp', 'chrome'),
        "serverName": sni,
        "password": getParam('pbk'),
        "shortId": getParam('sid'),
        "spiderX": getParam('spx')
      };
    }

    if (type == 'tcp' && getParam('headerType') == 'http') {
      stream['tcpSettings'] = {
        "header": {
          "type": "http",
          "request": {"headers": {"Host": [getParam('host', address)]}}
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
      final xhttpSettings = <String, dynamic>{"path": getParam('path', '/')};
      final host = getParam('host');
      xhttpSettings['host'] = host.isNotEmpty ? host : sni;
      final xhttpMode = getParam('mode');
      if (xhttpMode.isNotEmpty) xhttpSettings['mode'] = xhttpMode;
      stream['xhttpSettings'] = xhttpSettings;
    } else if (type == 'httpupgrade') {
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
          return 'regexp:.*\\.${cleaned}\$';
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
        "port": "53",
        "network": "udp",
        "outboundTag": "dns-out"
      });
    }

    rules.add({
      "ip": ["169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"],
      "outboundTag": "block"
    });

    if (blockedDomains.isNotEmpty) {
      rules.add({"domain": blockedDomains, "outboundTag": "block"});
    }

    if (mode == VpnMode.systemProxy) {
      final isIpAddress = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(address);
      if (isIpAddress) {
        rules.add({"ip": [address], "outboundTag": "direct"});
      } else {
        rules.add({"domain": ["full:$address"], "outboundTag": "direct"});
      }
    }

    if (directDomains.isNotEmpty) {
      rules.add({"domain": directDomains, "outboundTag": "direct"});
    }
    if (directIps.isNotEmpty) {
      rules.add({"ip": directIps, "outboundTag": "direct"});
    }

    rules.add({"ip": ["geoip:private"], "outboundTag": "direct"});

    if (proxyDomains.isNotEmpty) {
      rules.add({"domain": proxyDomains, "outboundTag": "proxy"});
    }

    rules.add({"outboundTag": "proxy", "network": "tcp,udp"});

    final config = <String, dynamic>{
      "log": {"loglevel": "warning"},
      "inbounds": <Map<String, dynamic>>[],
      "outbounds": <Map<String, dynamic>>[
        outbound,
        <String, dynamic>{"protocol": "freedom", "tag": "direct"},
        <String, dynamic>{"protocol": "blackhole", "tag": "block"}
      ],
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
      config["outbounds"].add(<String, dynamic>{"protocol": "dns", "tag": "dns-out"});
    }

    if (mode == VpnMode.tun) {
      config['inbounds'].add({
        "tag": "socks-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {"udp": true, "ip": "127.0.0.1"},
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic", "fakedns"]
        }
      });
    } else {
      config['inbounds'].add({
        "tag": "mixed-in",
        "port": settings.localPort,
        "listen": "127.0.0.1",
        "protocol": "mixed",
        "settings": {"udpEnabled": true},
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic", "fakedns"]
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
        if (cleaned.isEmpty) return '';
        return '.$cleaned';
      }).where((d) => d.isNotEmpty && d != '.').toList();
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

    if (directDomains.isNotEmpty && routingMode != AppRoutingMode.allProxy) {
      rules.add({
        "action": "route",
        "outbound": "direct",
        "domain_suffix": directDomains,
      });
    }

    if (directIps.isNotEmpty && routingMode != AppRoutingMode.allProxy) {
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

    final dnsFinal = (routingMode == AppRoutingMode.onlySelected)
        ? "local-dns"
        : "remote-dns";

    final dnsRules = <Map<String, dynamic>>[];

    if (vpnProcessNames.isNotEmpty && routingMode == AppRoutingMode.onlySelected) {
      dnsRules.add({
        "action": "route",
        "process_name": vpnProcessNames,
        "server": "remote-dns"
      });
    }

    if (directDomains.isNotEmpty && routingMode != AppRoutingMode.allProxy) {
      dnsRules.add({
        "action": "route",
        "domain_suffix": directDomains,
        "server": "local-dns"
      });
    }

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
