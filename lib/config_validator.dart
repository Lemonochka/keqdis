class ConfigValidator {
  static bool isVlessConfig(String config) {
    return config.startsWith('vless://');
  }

  static bool isVmessConfig(String config) {
    return config.startsWith('vmess://');
  }

  static bool isTrojanConfig(String config) {
    return config.startsWith('trojan://');
  }

  static bool isValidConfig(String config) {
    return isVlessConfig(config) ||
        isVmessConfig(config) ||
        isTrojanConfig(config);
  }

  static String getConfigType(String config) {
    if (isVlessConfig(config)) return "VLESS";
    if (isVmessConfig(config)) return "VMESS";
    if (isTrojanConfig(config)) return "Trojan";
    return "Неизвестный";
  }
}