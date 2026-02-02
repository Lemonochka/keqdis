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
    if (!Platform.isWindows) return false;
    return await hasAdminRights();
  }

  static Future<void> prepareWintunDll(String xrayDir) async {
    final dllPath = path.join(xrayDir, _wintunDllName);
    final dllFile = File(dllPath);
    if (await dllFile.exists()) return;

    try {
      final data = await rootBundle.load('assets/bin/$_wintunDllName');
      final bytes = data.buffer.asUint8List();
      await dllFile.writeAsBytes(bytes, flush: true);
      print('✅ wintun.dll скопирован');
    } catch (e) {
      print('❌ Ошибка копирования wintun.dll: $e');
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

  /// TUN конфиг
  static Map<String, dynamic> createTunInbound() {
    return <String, dynamic>{
      "tag": "tun-in",
      "protocol": "tun",
      "settings": <String, dynamic>{
        "name": "keqdis-tun",
        "mtu": 1280, // Уменьшили MTU для стабильности
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

  /// ПОЛУЧАЕМ ЛОКАЛЬНЫЙ IP АДРЕС АКТИВНОГО АДАПТЕРА
  /// Это намного надежнее для Windows, чем имя интерфейса
  static Future<String> getActiveInterfaceIp() async {
    try {
      // PowerShell: Найти активный адаптер и взять его IPv4 адрес
      const psCommand = r'Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false -and $_.InterfaceDescription -notlike "*TAP*" -and $_.InterfaceDescription -notlike "*Hyper-V*" } | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress -First 1';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', psCommand],
        runInShell: true,
      );

      final ip = result.stdout.toString().trim();

      // Простейшая валидация IP
      if (ip.isNotEmpty && ip.split('.').length == 4) {
        print('✅ (PowerShell) Найден IP интерфейса: "$ip"');
        return ip;
      }

      print('⚠️ Не удалось определить IP, возвращаем пустоту');
      return '';
    } catch (e) {
      print('⚠️ Ошибка получения IP: $e');
      return '';
    }
  }

  // Заглушки
  static Future<bool> addTunRoute() async => true;
  static Future<void> removeTunRoute() async {}
  static Future<bool> requestAdminRights() async {
    if (kDebugMode) return false;
    final exe = Platform.resolvedExecutable;
    try {
      await Process.run('powershell', ['Start-Process', '"$exe"', '-Verb', 'RunAs']);
      return true;
    } catch (e) { return false; }
  }
}