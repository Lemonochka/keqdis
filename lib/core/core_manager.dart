import 'dart:io';
import 'service.dart';
import '../utils/config_gen.dart';
import 'system_proxy.dart';
import '../storages/improved_settings_storage.dart';
import 'tun_service.dart';

class CoreManager {
  final _xrayService = VpnService();
  final _singboxService = VpnService();

  VpnMode _currentMode = VpnMode.systemProxy;

  bool get isRunning => _xrayService.isRunning;
  VpnMode get currentMode => _currentMode;

  Future<void> start(String configInput, {VpnMode mode = VpnMode.systemProxy}) async {
    await stop();

    final settings = await SettingsStorage.loadSettings();
    final localPort = settings.localPort;

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
        try {
          final ips = await InternetAddress.lookup(host);
          if (ips.isNotEmpty) {
            serverIpToExclude = ips.first.address;
            resolvedConfigInput = configInput.replaceFirst(host, serverIpToExclude);
          }
        } catch (e) {
          throw Exception('Не удалось отрезолвить домен сервера. Проверьте интернет-соединение.');
        }
      } else if (isIp) {
        serverIpToExclude = host;
      }
    }

    final xrayConfig = ConfigGeneratorV2.generateConfig(
      resolvedConfigInput,
      settings,
      mode: mode,
      adapterIp: '',
    );

    await _xrayService.start(xrayConfig, executableName: 'xray.exe');

    if (mode == VpnMode.systemProxy) {
      await SystemProxy.setHTTPProxy(address: '127.0.0.1:$localPort');
    } else if (mode == VpnMode.tun) {
      final dir = await _singboxService.getXrayDir();
      await TunService.prepareWintunDll(dir);

      final singboxConfig = SingBoxChainGen.generateTunConfig(
        localSocksPort: localPort,
        serverIpToExclude: serverIpToExclude,
        settings: settings,
      );

      await _singboxService.start(
          singboxConfig,
          executableName: 'sing-box.exe',
          args: ['run', '-c', 'config.json']
      );
    }

    _currentMode = mode;
  }

  Future<void> switchMode(String configInput, VpnMode newMode) async {
    if (newMode == _currentMode) {
      return;
    }

    await start(configInput, mode: newMode);
  }

  Future<void> stop() async {
    if (_singboxService.isRunning) {
      await _singboxService.stop();
    }
    if (_xrayService.isRunning) {
      await _xrayService.stop();
    }

    await SystemProxy.clearProxy();
  }
}