import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;

enum VpnMode {
  systemProxy,
  tun,
}

class TunService {
  static const String _wintunDllName = 'wintun.dll';

  static Future<bool> isTunAvailable() async {
    // TUN mode is only supported on Windows.
    return Platform.isWindows;
  }

  static Future<void> prepareWintunDll(String xrayDir) async {
    final dllPath = path.join(xrayDir, _wintunDllName);
    final dllFile = File(dllPath);
    if (await dllFile.exists()) return;

    try {
      final data = await rootBundle.load('assets/bin/$_wintunDllName');
      await dllFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } catch (e, s) {
      debugPrint('Failed to prepare $_wintunDllName: $e\n$s');
      throw Exception('Failed to prepare $_wintunDllName. TUN mode will not work.');
    }
  }

  static Future<bool> hasAdminRights() async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      // Running 'fltmc filters' requires elevation and is a reliable way
      // to check for admin rights without making permanent system changes.
      final result = await Process.run('fltmc', ['filters'], runInShell: true);
      return result.exitCode == 0;
    } catch (e, s) {
      debugPrint('Admin rights check failed: $e\n$s');
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
      // Use Dart's native NetworkInterface to avoid spawning a process.
      // This is much more efficient and platform-agnostic.
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      
      // Prefer interfaces that are likely physical connections.
      final preferredInterfaces = interfaces.where((iface) {
        final name = iface.name.toLowerCase();
        return name.contains('ethernet') || name.contains('wi-fi') || name.contains('wlan');
      });

      final potentialInterfaces = preferredInterfaces.isNotEmpty ? preferredInterfaces : interfaces;

      for (final interface in potentialInterfaces) {
        for (final addr in interface.addresses) {
          // Filter out link-local addresses.
          if (!addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e, s) {
      debugPrint('Could not get active IP address: $e\n$s');
    }
    return ''; // Fallback
  }

  // These methods are placeholders. Routing is handled by xray-core's
  // 'autoRoute: true' setting in the TUN inbound configuration.
  static Future<bool> addTunRoute() async => true;
  static Future<void> removeTunRoute() async {}

  static Future<bool> requestAdminRights() async {
    if (kDebugMode || !Platform.isWindows) return false;
    final exe = Platform.resolvedExecutable;
    try {
      await Process.start('powershell', ['Start-Process', '"$exe"', '-Verb', 'RunAs'], runInShell: true, mode: ProcessStartMode.detached);
      // We can't be certain it succeeded, but we have requested it.
      // The app will likely restart.
      return true;
    } catch (e, s) {
      debugPrint('Failed to request admin rights: $e\n$s');
      return false;
    }
  }
}
