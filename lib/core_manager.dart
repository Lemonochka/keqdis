import 'dart:io';
import 'service.dart';
import 'config_gen.dart';
import 'system_proxy.dart';
import 'improved_settings_storage.dart';
import 'tun_service.dart';

class CoreManager {
  // Нам нужны два сервиса: один для Xray, второй для Sing-box
  final _xrayService = VpnService();
  final _singboxService = VpnService();

  VpnMode _currentMode = VpnMode.systemProxy;

  bool get isRunning => _xrayService.isRunning;
  VpnMode get currentMode => _currentMode;

  Future<void> start(String configInput, {VpnMode mode = VpnMode.systemProxy}) async {
    // 1. Останавливаем всё
    await stop();

    final settings = await SettingsStorage.loadSettings();
    final localPort = settings.localPort;

    // 2. Для TUN режима резолвим домен ПЕРЕД генерацией конфига
    String resolvedConfigInput = configInput;
    String serverIpToExclude = '';

    if (mode == VpnMode.tun) {
      if (!await TunService.hasAdminRights()) {
        throw Exception('Нужны права администратора');
      }

      final uri = Uri.tryParse(configInput.trim());
      String host = uri?.host ?? '';
      final isIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(host);

      if (!isIp && host.isNotEmpty) {
        print('🔍 Резолвим домен сервера: $host');
        try {
          final ips = await InternetAddress.lookup(host);
          if (ips.isNotEmpty) {
            serverIpToExclude = ips.first.address;
            print('✅ Домен $host → IP $serverIpToExclude');

            // КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: заменяем домен на IP в URL для Xray
            // Это предотвращает использование FakeDNS для сервера VPN
            resolvedConfigInput = configInput.replaceFirst(host, serverIpToExclude);
            print('📝 Обновленный конфиг использует IP: $serverIpToExclude');
          }
        } catch (e) {
          print('⚠️ Ошибка резолва $host: $e');
          throw Exception('Не удалось отрезолвить домен сервера. Проверьте интернет-соединение.');
        }
      } else if (isIp) {
        serverIpToExclude = host;
        print('✅ Сервер уже использует IP: $serverIpToExclude');
      }
    }

    // 3. Генерируем Xray Config
    final xrayConfig = ConfigGeneratorV2.generateConfig(
      resolvedConfigInput, // Для TUN используем IP, для systemProxy - как есть
      settings,
      mode: mode,
      adapterIp: '',
    );

    print('🚀 Запуск Xray Core...');
    await _xrayService.start(xrayConfig, executableName: 'xray.exe');

    if (mode == VpnMode.systemProxy) {
      await SystemProxy.setHTTPProxy(address: '127.0.0.1:$localPort');
      print('✅ Установлен системный прокси');
    } else if (mode == VpnMode.tun) {
      // --- РЕЖИМ TUN ---
      final dir = await _singboxService.getXrayDir();
      await TunService.prepareWintunDll(dir);

      print('🛡️ Исключаем IP сервера из TUN: $serverIpToExclude');

      final singboxConfig = SingBoxChainGen.generateTunConfig(
        localSocksPort: localPort,
        serverIpToExclude: serverIpToExclude,
        settings: settings, // Передаем настройки для роутинга!
      );

      print('🛡️ Запуск Sing-box Tun...');
      await _singboxService.start(
          singboxConfig,
          executableName: 'sing-box.exe',
          args: ['run', '-c', 'config.json']
      );
    }

    _currentMode = mode;
  }

  /// Переключение режима на лету
  Future<void> switchMode(String configInput, VpnMode newMode) async {
    if (newMode == _currentMode) {
      print('⚠️ Режим уже установлен: $newMode');
      return;
    }

    print('🔄 Переключение режима: $_currentMode -> $newMode');

    // Просто перезапускаем с новым режимом
    await start(configInput, mode: newMode);
  }

  Future<void> stop() async {
    // Сначала убиваем TUN, чтобы вернуть интернет
    if (_singboxService.isRunning) {
      await _singboxService.stop();
    }
    // Потом убиваем Xray
    if (_xrayService.isRunning) {
      await _xrayService.stop();
    }

    await SystemProxy.clearProxy();
    // TunService.removeTunRoute() больше не нужен, Sing-box чистит за собой сам
  }
}