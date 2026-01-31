import 'service.dart';
import 'config_gen.dart';
import 'system_proxy.dart';
import 'improved_settings_storage.dart';

class CoreManager {
  final _vpnService = VpnService();

  bool get isRunning => _vpnService.isRunning;

  Future<void> start(String config, {bool useSystemProxy = true}) async {
    await stop();

    // 1. Загружаем настройки
    final settings = await SettingsStorage.loadSettings();

    // 2. Генерируем конфиг с учетом настроек
    final jsonConfig = ConfigGenerator.generateConfig(config, settings);

    // 3. Запускаем Xray
    await _vpnService.start(jsonConfig);

    // 4. Ставим системный прокси на нужный порт
    if (useSystemProxy) {
      await SystemProxy.setHTTPProxy(
          address: '127.0.0.1:${settings.localPort}'
      );
    }
  }

  Future<void> stop() async {
    await _vpnService.stop();
  }

  // ... (getServerName остается без изменений) ...
  String getServerName(String config) {
    try {
      if (config.startsWith('vless://')) {
        final uri = Uri.tryParse(config);
        if (uri != null) {
          return uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : uri.host;
        }
      }
      return "Server";
    } catch (e) {
      return "Unknown";
    }
  }
}