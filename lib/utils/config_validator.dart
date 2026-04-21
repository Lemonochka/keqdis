// FIX: Ограничена валидация до реально поддерживаемых протоколов.
// Если вы добавите поддержку VMess/Trojan в config_gen.dart,
// раскомментируйте соответствующие методы.

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

  // FIX: isValidConfig возвращает true только для поддерживаемых в config_gen.dart протоколов
  // Сейчас ConfigGeneratorV2 поддерживает ТОЛЬКО VLESS.
  // Когда добавите VMess/Trojan — раскомментируйте строки ниже.
  static bool isValidConfig(String config) {
    return isVlessConfig(config) ||
        isTrojanConfig(config) ||
        isShadowsocksConfig(config);
    // || isVmessConfig(config);   // TODO: раскомментировать после добавления поддержки
  }

  static String getConfigType(String config) {
    if (isVlessConfig(config)) return "VLESS";
    if (isVmessConfig(config)) return "VMESS";
    if (isTrojanConfig(config)) return "Trojan";
    if (isShadowsocksConfig(config)) return "Shadowsocks";
    return "Неизвестный";
  }

  // FIX: Добавлен метод для проверки поддержки генерации конфига
  static bool isGenerationSupported(String config) {
    return isVlessConfig(config) ||
        isTrojanConfig(config) ||
        isShadowsocksConfig(config);
  }

  // FIX: Человекочитаемая ошибка для неподдерживаемого протокола
  static String? getUnsupportedReason(String config) {
    if (isVmessConfig(config)) {
      return 'Протокол VMess пока не поддерживается генератором конфигов. '
          'Планируется в будущей версии.';
    }
    if (isTrojanConfig(config)) {
      return null;
    }
    if (isShadowsocksConfig(config)) {
      return null;
    }
    if (!isValidConfig(config)) {
      return 'Неизвестный формат конфигурации. Поддерживается: VLESS, Trojan, Shadowsocks.';
    }
    return null;
  }
}
