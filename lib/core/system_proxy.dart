import 'dart:io';

class SystemProxy {
  static bool _isValidProxyAddress(String address) {
    final pattern = RegExp(r'^((\d{1,3}\.){3}\d{1,3}|localhost|127\.0\.0\.1):\d{1,5}$');

    if (!pattern.hasMatch(address)) {
      return false;
    }

    final parts = address.split(':');
    if (parts.length != 2) return false;

    try {
      final port = int.parse(parts[1]);
      if (port < 1 || port > 65535) {
        return false;
      }
    } catch (e) {
      return false;
    }

    if (parts[0] != 'localhost' && !parts[0].startsWith('127.')) {
      final ipParts = parts[0].split('.');
      if (ipParts.length != 4) return false;

      for (final part in ipParts) {
        try {
          final num = int.parse(part);
          if (num < 0 || num > 255) {
            return false;
          }
        } catch (e) {
          return false;
        }
      }
    }

    return true;
  }

  static Future<void> setHTTPProxy({String address = '127.0.0.1:2080'}) async {
    if (!_isValidProxyAddress(address)) {
      throw ArgumentError('Некорректный адрес прокси: $address');
    }

    try {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        address,
        '/f'
      ]);

      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f'
      ]);
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> setSOCKSProxy({String address = '127.0.0.1:1080'}) async {
    if (!_isValidProxyAddress(address)) {
      throw ArgumentError('Некорректный адрес прокси: $address');
    }

    try {
      final proxyValue = 'socks=$address';

      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
        '/t',
        'REG_SZ',
        '/d',
        proxyValue,
        '/f'
      ]);

      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '1',
        '/f'
      ]);
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> clearProxy() async {
    try {
      await Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
        '/t',
        'REG_DWORD',
        '/d',
        '0',
        '/f'
      ]);
    } catch (e) {
      // Ignore errors during cleanup
    }
  }

  static Future<ProxyState> getProxyState() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final enabled = output.contains('0x1');

        if (enabled) {
          final addressResult = await Process.run('reg', [
            'query',
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
            '/v',
            'ProxyServer',
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
        }
      }

      return ProxyState(enabled: false);
    } catch (e) {
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