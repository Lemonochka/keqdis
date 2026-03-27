import 'dart:io';
import 'package:flutter/material.dart';
import 'service.dart';
import '../utils/config_gen.dart';
import 'system_proxy.dart';
import '../storages/improved_settings_storage.dart';
import '../storages/app_routing_storage.dart';
import 'tun_service.dart';

class CoreManager extends ChangeNotifier {
  // FIX: Оставляем оригинальный конструктор VpnService() без параметров
  final _xrayService = VpnService();
  final _singboxService = VpnService();

  VpnMode _currentMode = VpnMode.systemProxy;

  CoreManager() {
    // FIX: Подписываемся на изменения состояния ядер
    _xrayService.onStateChanged = () => notifyListeners();
    _singboxService.onStateChanged = () => notifyListeners();
  }

  // FIX: В TUN-режиме проверяем оба сервиса
  bool get isRunning {
    if (_currentMode == VpnMode.tun) {
      return _xrayService.isRunning && _singboxService.isRunning;
    }
    return _xrayService.isRunning;
  }

  VpnMode get currentMode => _currentMode;

  Future<void> start(String configInput, {VpnMode mode = VpnMode.systemProxy}) async {
    await stop();

    final settings = await SettingsStorage.loadSettings();
    final localPort = settings.localPort;

    String resolvedConfigInput = configInput;
    String serverIpToExclude = '';
    // FIX: Получаем реальный IP адаптера для TUN-режима
    String adapterIp = '';

    if (mode == VpnMode.tun) {
      if (!await TunService.hasAdminRights()) {
        throw Exception('Нужны права администратора');
      }

      // FIX: Получаем IP активного сетевого интерфейса
      adapterIp = await TunService.getActiveInterfaceIp();
      if (adapterIp.isEmpty) {
        debugPrint('CoreManager: WARNING - не удалось определить IP адаптера');
      }

      final uri = Uri.tryParse(configInput.trim());
      String host = uri?.host ?? '';
      final isIp = _isValidIPv4(host);

      if (!isIp && host.isNotEmpty) {
        try {
          final ips = await InternetAddress.lookup(host);
          if (ips.isNotEmpty) {
            serverIpToExclude = ips.first.address;
            resolvedConfigInput = configInput.replaceFirst(host, serverIpToExclude);
          }
        } catch (e) {
          throw Exception('Не удалось резолвить домен сервера: $e');
        }
      } else if (isIp) {
        serverIpToExclude = host;
      }
    }

    // FIX: try-catch с откатом при частичном запуске
    try {
      final xrayConfig = ConfigGeneratorV2.generateConfig(
        resolvedConfigInput,
        settings,
        mode: mode,
        adapterIp: adapterIp, // FIX: Передаём реальный IP вместо пустой строки
      );

      // FIX: xray пишет в config.json (по умолчанию) — без изменений
      await _xrayService.start(xrayConfig, executableName: 'xray.exe');

      if (mode == VpnMode.systemProxy) {
        await SystemProxy.setHTTPProxy(address: '127.0.0.1:$localPort');
      } else if (mode == VpnMode.tun) {
        final dir = await _singboxService.getXrayDir();
        await TunService.prepareWintunDll(dir);

        final routingData = await AppRoutingStorage.load();
        final vpnProcessNames = routingData.apps.toList();

        final singboxConfig = SingBoxChainGen.generateTunConfig(
          localSocksPort: localPort,
          serverIpToExclude: serverIpToExclude,
          settings: settings,
          vpnProcessNames: vpnProcessNames,
          routingMode: routingData.mode,
        );

        // FIX: sing-box использует отдельный файл singbox_config.json
        // чтобы не перезаписывать конфиг xray
        await _singboxService.start(
          singboxConfig,
          executableName: 'sing-box.exe',
          configFileName: 'singbox_config.json', // FIX: новый параметр в start()
          args: ['run', '-c', 'singbox_config.json'],
        );
      }

      _currentMode = mode;
      notifyListeners();
    } catch (e) {
      // FIX: Откатываем частично запущенные сервисы при ошибке
      debugPrint('CoreManager: Start failed, rolling back: $e');
      await stop();
      rethrow;
    }
  }

  Future<void> switchMode(String configInput, VpnMode newMode) async {
    if (newMode == _currentMode && isRunning) {
      return;
    }
    await start(configInput, mode: newMode);
  }

  Future<void> stop() async {
    final wasRunning = isRunning;

    if (_singboxService.isRunning) {
      await _singboxService.stop();
    }
    if (_xrayService.isRunning) {
      await _xrayService.stop();
    }

    await SystemProxy.clearProxy();

    if (wasRunning) {
      notifyListeners();
    }
  }

  // FIX: Улучшенная валидация IPv4
  static bool _isValidIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }
}
