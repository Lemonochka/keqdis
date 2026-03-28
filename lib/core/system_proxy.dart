import 'dart:io';
import 'package:flutter/foundation.dart';

class SystemProxy {
  static bool _isValidProxyAddress(String address) {
    final uri = Uri.tryParse('tcp://$address');
    if (uri == null || uri.host.isEmpty || uri.port == 0) {
      return false;
    }
    return true;
  }

  // FIX: Разделили на два метода — строгий и мягкий
  // Строгий — для set-операций, где ошибка критична
  static Future<void> _runRegCommand(List<String> args) async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('reg', args, runInShell: true);
      if (result.exitCode != 0) {
        throw Exception('REG command failed with exit code ${result.exitCode}: ${result.stderr}');
      }
    } catch (e, s) {
      debugPrint('Failed to execute REG command: $e\n$s');
      rethrow;
    }
  }

  // FIX: Мягкий вариант — для cleanup-операций, где ошибка не критична
  // Возвращает bool вместо throw, не печатает stack trace
  static Future<bool> _tryRunRegCommand(List<String> args) async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run('reg', args, runInShell: true);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  static Future<void> _setSystemProxy(String address) async {
    await _runRegCommand([
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyServer',
      '/t', 'REG_SZ',
      '/d', address,
      '/f'
    ]);

    await _runRegCommand([
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable',
      '/t', 'REG_DWORD',
      '/d', '1',
      '/f'
    ]);
  }

  static Future<void> setHTTPProxy({String address = '127.0.0.1:2080'}) async {
    if (!_isValidProxyAddress(address)) {
      throw ArgumentError('Некорректный адрес прокси: $address');
    }
    await _setSystemProxy(address);
  }

  static Future<void> setSOCKSProxy({String address = '127.0.0.1:1080'}) async {
    if (!_isValidProxyAddress(address)) {
      throw ArgumentError('Некорректный адрес прокси: $address');
    }
    final proxyValue = 'socks=$address';
    await _setSystemProxy(proxyValue);
  }

  // FIX: clearProxy использует _tryRunRegCommand — cleanup не должен ломать flow приложения
  static Future<void> clearProxy() async {
    if (!Platform.isWindows) return;

    // Отключаем прокси (reg add создаёт ключ если его нет — не должен падать)
    final disableOk = await _tryRunRegCommand([
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable',
      '/t', 'REG_DWORD',
      '/d', '0',
      '/f'
    ]);

    if (!disableOk) {
      debugPrint('SystemProxy: Failed to disable ProxyEnable (non-critical)');
    }

    // FIX: Удаляем ProxyServer — используем мягкий метод, т.к. ключ может не существовать
    final deleteOk = await _tryRunRegCommand([
      'delete',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyServer',
      '/f'
    ]);

    if (!deleteOk) {
      debugPrint('SystemProxy: ProxyServer key not found or could not be deleted (non-critical)');
    }
  }

  static Future<ProxyState> getProxyState() async {
    if (!Platform.isWindows) return ProxyState(enabled: false);

    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable',
      ]);

      if (result.exitCode != 0) {
        return ProxyState(enabled: false);
      }

      final output = result.stdout.toString();
      final isEnabled = output.contains(RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1'));

      if (!isEnabled) {
        return ProxyState(enabled: false);
      }

      final addressResult = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer',
      ]);

      if (addressResult.exitCode == 0) {
        final addressOutput = addressResult.stdout.toString();
        final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(addressOutput);
        if (match != null) {
          return ProxyState(
            enabled: true,
            address: match.group(1)?.trim(),
          );
        }
      }

      return ProxyState(enabled: true);
    } catch (e, s) {
      debugPrint('Failed to get proxy state: $e\n$s');
      return ProxyState(enabled: false);
    }
  }
}

class ProxyState {
  final bool enabled;
  final String? address;

  ProxyState({
    required this.enabled,
    this.address,
  });

  @override
  String toString() {
    if (enabled && address != null) {
      return 'Прокси включен: $address';
    } else if (enabled) {
      return 'Прокси включен';
    } else {
      return 'Прокси отключен';
    }
  }
}
