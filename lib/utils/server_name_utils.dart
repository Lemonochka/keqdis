/// Утилита для работы с названиями серверов
class ServerNameUtils {

  static String? extractCountryCode(String displayName) {
    // Удаляем эмодзи флаги если есть
    final cleaned = displayName.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '').trim();

    // Ищем код страны (2 заглавные буквы в начале)
    final regex = RegExp(r'^([A-Z]{2})\s');
    final match = regex.firstMatch(cleaned);

    return match?.group(1);
  }

  static String cleanDisplayName(String displayName) {
    var cleaned = displayName.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '').trim();

    final regex = RegExp(r'^[A-Z]{2}\s+(.+)$');
    final match = regex.firstMatch(cleaned);

    if (match != null) {
      return match.group(1)!.trim();
    }

    return cleaned;
  }

  static String formatForDisplay(String displayName, {int maxLength = 30}) {
    final cleaned = cleanDisplayName(displayName);

    if (cleaned.length <= maxLength) {
      return cleaned;
    }

    return '${cleaned.substring(0, maxLength - 3)}...';
  }
}