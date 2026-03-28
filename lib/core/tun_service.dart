import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

enum VpnMode {
  systemProxy,
  tun,
}

class TunService {
  static const String _wintunDllName = 'wintun.dll';

  static Future<bool> isTunAvailable() async {
    if (!Platform.isWindows) return false;
    return await hasAdminRights();
  }

  static Future<void> prepareWintunDll(String xrayDir) async {
    final dllPath = path.join(xrayDir, _wintunDllName);
    final dllFile = File(dllPath);
    if (await dllFile.exists()) return;

    // FIX: Пробрасываем ошибку вместо проглатывания — без wintun.dll sing-box не запустится
    try {
      final data = await rootBundle.load('assets/bin/$_wintunDllName');
      final bytes = data.buffer.asUint8List();
      await dllFile.writeAsBytes(bytes, flush: true);
    } catch (e) {
      throw Exception(
          'Не удалось подготовить wintun.dll: $e. '
              'Sing-box не сможет запуститься без этого файла.'
      );
    }
  }

  static Future<bool> hasAdminRights() async {
    try {
      final result = await Process.run('net', ['session'], runInShell: true);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  static Map<String, dynamic> createTunInbound() {
    return {
      "tag": "tun-in",
      "protocol": "tun",
      "settings": {
        "name": "keqdis-tun",
        "mtu": 1280,
        "address": ["172.19.0.1/30"],
        "autoRoute": true,
        "strictRoute": true,
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    };
  }

  static Future<String> getActiveInterfaceIp() async {
    try {
      const psCommand = r'Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and $_.InterfaceDescription -notlike "*TAP*" -and $_.InterfaceDescription -notlike "*Hyper-V*" -and $_.InterfaceDescription -notlike "*tun*" -and $_.InterfaceDescription -notlike "*WireGuard*" } | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress -First 1';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', psCommand],
        runInShell: true,
      ).timeout(const Duration(seconds: 5)); // FIX: Добавлен таймаут

      final ip = result.stdout.toString().trim();

      // FIX: Улучшенная валидация IP
      if (ip.isNotEmpty && _isValidIPv4(ip)) {
        return ip;
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  // FIX: Вынесенная валидация IPv4
  static bool _isValidIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }

  static Future<bool> addTunRoute() async => true;
  static Future<void> removeTunRoute() async {}

  static Future<bool> requestAdminRights() async {
    if (!Platform.isWindows) return false;

    try {
      final exe = Platform.resolvedExecutable;
      final psCommand =
          'Start-Process -FilePath \'${exe.replaceAll("'", "''")}\' -Verb RunAs';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psCommand],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        exit(0);
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
