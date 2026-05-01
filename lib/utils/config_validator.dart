class ConfigValidator {
  static bool isVlessConfig(String config) {
    return config.trimLeft().startsWith('vless://');
  }

  static bool isVmessConfig(String config) {
    return config.trimLeft().startsWith('vmess://');
  }

  static bool isTrojanConfig(String config) {
    return config.trimLeft().startsWith('trojan://');
  }

  static bool isShadowsocksConfig(String config) {
    return config.trimLeft().startsWith('ss://');
  }

  static bool isHysteriaConfig(String config) {
    final trimmed = config.trimLeft();
    return trimmed.startsWith('hysteria://') || trimmed.startsWith('hy2://');
  }

  // isValidConfig returns true only for supported generator protocols
  static bool isValidConfig(String config) {
    return isVlessConfig(config) ||
        isVmessConfig(config) ||
        isTrojanConfig(config) ||
        isShadowsocksConfig(config) ||
        isHysteriaConfig(config);
  }

  static String getConfigType(String config) {
    if (isVlessConfig(config)) return "VLESS";
    if (isVmessConfig(config)) return "VMESS";
    if (isTrojanConfig(config)) return "Trojan";
    if (isShadowsocksConfig(config)) return "Shadowsocks";
    if (isHysteriaConfig(config)) return "Hysteria";
    return "Неизвестный";
  }

  static bool isGenerationSupported(String config) {
    return isVlessConfig(config) ||
        isVmessConfig(config) ||
        isTrojanConfig(config) ||
        isShadowsocksConfig(config) ||
        isHysteriaConfig(config);
  }

  // ошибка для неподдерживаемого протокола
  static String? getUnsupportedReason(String config) {
    if (!isValidConfig(config)) {
      return 'Неизвестный формат конфигурации. Поддерживается: VLESS, VMess, Trojan, Shadowsocks, Hysteria.';
    }
    return null;
  }
}
