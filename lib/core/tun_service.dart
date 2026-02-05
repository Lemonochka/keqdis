import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

enum VpnMode {
  systemProxy,
  tun,
}

class TunService {
  static const String _wintunDllName = 'wintun.dll';

  static Future<bool> isTunAvailable() async {
    // TUN режим поддерживается только в Windows. UI обработает проверку прав администратора,
    // когда пользователь попытается его включить.
    return Platform.isWindows;
  }

  static Future<void> prepareWintunDll(String xrayDir) async {
    final dllPath = path.join(xrayDir, _wintunDllName);
    final dllFile = File(dllPath);
    if (await dllFile.exists()) return;

    try {
      final data = await rootBundle.load('assets/bin/$_wintunDllName');
      final bytes = data.buffer.asUint8List();
      await dllFile.writeAsBytes(bytes, flush: true);
    } catch (e) {
      // Не удалось подготовить wintun.dll
    }
  }

  static Future<bool> hasAdminRights() async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      // Это более надежный способ проверки прав администратора.
      // Команда 'net session' может вводить в заблуждение.
      // Мы пытаемся выполнить команду, требующую повышения прав.
      final result = await Process.run('fltmc', ['filters'], runInShell: true);
      // Код выхода 0 означает успех. Любой другой код означает неудачу.
      return result.exitCode == 0;
    } catch (e) {
      // Если команду не удается выполнить, предполагаем, что права администратора отсутствуют.
      return false;
    }
  }

  static Map<String, dynamic> createTunInbound() {
    return <String, dynamic>{
      "tag": "tun-in",
      "protocol": "tun",
      "settings": <String, dynamic>{
        "name": "keqdis-tun",
        "mtu": 1280,
        "address": ["172.19.0.1/30"],
        "autoRoute": true,
        "strictRoute": true,
      },
      "sniffing": <String, dynamic>{
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    };
  }

  static Future<String> getActiveInterfaceIp() async {
    try {
      const psCommand = r'Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and $_.InterfaceDescription -notlike "*TAP*" -and $_.InterfaceDescription -notlike "*Hyper-V*" } | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress -First 1';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', psCommand],
        runInShell: true,
      );

      final ip = result.stdout.toString().trim();

      if (ip.isNotEmpty && ip.split('.').length == 4) {
        return ip;
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  static Future<bool> addTunRoute() async => true;
  static Future<void> removeTunRoute() async {}
  static Future<bool> requestAdminRights() async {
    if (kDebugMode) return false;
    final exe = Platform.resolvedExecutable;
    try {
      await Process.run('powershell', ['Start-Process', '"$exe"', '-Verb', 'RunAs']);
      return true;
    } catch (e) {
      return false;
    }
  }
}