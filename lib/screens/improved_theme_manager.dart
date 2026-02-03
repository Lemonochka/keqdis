import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:file_picker/file_picker.dart';
import '../storages/unified_storage.dart';

class ThemeSettings {
  String? backgroundImagePath;
  Color primaryColor;
  Color secondaryColor;
  Color accentColor;
  double backgroundOpacity;
  double blurIntensity;

  ThemeSettings({
    this.backgroundImagePath,
    this.primaryColor = const Color(0xFF6C63FF),
    this.secondaryColor = const Color(0xFF00D9FF),
    this.accentColor = const Color(0xFF1A1F3A),
    this.backgroundOpacity = 0.3,
    this.blurIntensity = 10.0,
  });

  Map<String, dynamic> toJson() => {
    'backgroundImagePath': backgroundImagePath,
    'primaryColor': primaryColor.value,
    'secondaryColor': secondaryColor.value,
    'accentColor': accentColor.value,
    'backgroundOpacity': backgroundOpacity,
    'blurIntensity': blurIntensity,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      backgroundImagePath: json['backgroundImagePath'],
      primaryColor: Color(json['primaryColor'] ?? 0xFF6C63FF),
      secondaryColor: Color(json['secondaryColor'] ?? 0xFF00D9FF),
      accentColor: Color(json['accentColor'] ?? 0xFF1A1F3A),
      backgroundOpacity: json['backgroundOpacity'] ?? 0.3,
      blurIntensity: json['blurIntensity'] ?? 10.0,
    );
  }
}

/// ОПТИМИЗИРОВАНО: Минимальное количество notifyListeners, ленивая загрузка изображений
class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeSettings _settings = ThemeSettings();
  ThemeSettings get settings => _settings;

  bool get hasCustomBackground => _settings.backgroundImagePath != null;

  static const int _maxImageSize = 10 * 1024 * 1024;

  static bool _isValidImageExtension(String path) {
    final extension = path.toLowerCase().split('.').last;
    const validExtensions = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};
    return validExtensions.contains(extension);
  }

  /// Загрузить тему из портативного хранилища
  Future<void> loadTheme() async {
    try {
      final filePath = await PortableStorage.getFilePath('theme.json');
      final file = File(filePath);

      if (!await file.exists()) {
        return;
      }

      final content = await file.readAsString();
      final decoded = Map<String, dynamic>.from(JsonDecoder().convert(content));

      final newSettings = ThemeSettings.fromJson(decoded);

      if (newSettings.backgroundImagePath != null) {
        final bgFile = File(newSettings.backgroundImagePath!);
        if (!await bgFile.exists()) {
          newSettings.backgroundImagePath = null;
        } else {
          final fileSize = await bgFile.length();
          if (fileSize > _maxImageSize) {
            await bgFile.delete();
            newSettings.backgroundImagePath = null;
          }
        }
      }

      _settings = newSettings;
      notifyListeners();
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  /// Сохранить тему в портативное хранилище
  Future<void> saveTheme() async {
    try {
      final filePath = await PortableStorage.getFilePath('theme.json');
      final file = File(filePath);
      final themeJson = JsonEncoder().convert(_settings.toJson());
      await file.writeAsString(themeJson);
      notifyListeners();
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  /// Выбрать фоновое изображение с проверкой безопасности
  Future<void> pickBackgroundImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;
        final sourceFile = File(sourcePath);

        if (!await sourceFile.exists()) {
          throw Exception('Файл не найден');
        }

        if (!_isValidImageExtension(sourcePath)) {
          throw Exception('Недопустимый формат изображения. Разрешены: JPG, PNG, WEBP, BMP');
        }

        final fileSize = await sourceFile.length();
        if (fileSize > _maxImageSize) {
          throw Exception('Файл слишком большой. Максимальный размер: ${_maxImageSize ~/ (1024 * 1024)} MB');
        }

        try {
          final bytes = await sourceFile.readAsBytes();
          await ui.instantiateImageCodec(bytes, targetWidth: 10, targetHeight: 10);
        } catch (e) {
          throw Exception('Файл не является корректным изображением');
        }

        final portableDir = await PortableStorage.getPortableDirectory();

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = sourcePath.split('.').last;
        final fileName = 'custom_background_$timestamp.$extension';
        final destPath = '$portableDir/$fileName';

        // Удаляем старое изображение
        if (_settings.backgroundImagePath != null) {
          try {
            final oldFile = File(_settings.backgroundImagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
          } catch (e) {
            // Игнорируем ошибки
          }
        }

        // Копируем новое изображение
        await sourceFile.copy(destPath);

        if (Platform.isWindows) {
          try {
            await Process.run('icacls', [
              destPath,
              '/inheritance:r',
              '/grant:r',
              '${Platform.environment['USERNAME']}:R'
            ]);
          } catch (e) {
            // Игнорируем ошибки
          }
        }

        // Извлекаем цвета
        await _extractColorsFromImage(destPath);

        _settings.backgroundImagePath = destPath;
        await saveTheme();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// ОПТИМИЗИРОВАННОЕ извлечение цветов из изображения
  Future<void> _extractColorsFromImage(String imagePath) async {
    ui.Image? image;

    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();

      if (imageBytes.length > _maxImageSize) {
        throw Exception('Изображение слишком большое');
      }

      // ОПТИМИЗАЦИЯ: Сильное сжатие для анализа
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 100, // Уменьшено с 200
        targetHeight: 100,
      );

      final frame = await codec.getNextFrame();
      image = frame.image;

      // ОПТИМИЗАЦИЯ: Меньше цветов для анализа
      final paletteGenerator = await PaletteGenerator.fromImage(
        image,
        maximumColorCount: 8, // Уменьшено с 16
      );

      final vibrant = paletteGenerator.vibrantColor?.color;
      final darkVibrant = paletteGenerator.darkVibrantColor?.color;
      final lightVibrant = paletteGenerator.lightVibrantColor?.color;
      final dominant = paletteGenerator.dominantColor?.color;

      _settings.primaryColor = vibrant ?? lightVibrant ?? dominant ?? const Color(0xFF6C63FF);
      _settings.secondaryColor = lightVibrant ?? vibrant?.withOpacity(0.8) ?? const Color(0xFF00D9FF);
      _settings.accentColor = darkVibrant ?? _darkenColor(dominant ?? _settings.primaryColor, 0.7) ?? const Color(0xFF1A1F3A);

      _settings.accentColor = _ensureContrast(_settings.accentColor);
      _settings.primaryColor = _ensureSaturation(_settings.primaryColor);
      _settings.secondaryColor = _ensureBrightness(_settings.secondaryColor);

    } catch (e) {
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);
    } finally {
      image?.dispose();
    }
  }

  Color? _darkenColor(Color color, double factor) {
    try {
      final hsl = HSLColor.fromColor(color);
      final darkened = hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0));
      return darkened.toColor();
    } catch (e) {
      return null;
    }
  }

  Color _ensureContrast(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness > 0.3) {
      return hsl.withLightness(0.15).toColor();
    }
    return color;
  }

  Color _ensureSaturation(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.5) {
      return hsl.withSaturation(0.7).toColor();
    }
    return color;
  }

  Color _ensureBrightness(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.5) {
      return hsl.withLightness(0.6).toColor();
    }
    return color;
  }

  Future<void> removeBackground() async {
    if (_settings.backgroundImagePath != null) {
      try {
        final file = File(_settings.backgroundImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Игнорируем ошибки
      }

      _settings.backgroundImagePath = null;
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);

      await saveTheme();
    }
  }

  // ОПТИМИЗАЦИЯ: Убрали отдельные notifyListeners - вызываем только в saveTheme
  void updateOpacity(double opacity) {
    _settings.backgroundOpacity = opacity.clamp(0.0, 1.0);
  }

  void updateBlur(double blur) {
    _settings.blurIntensity = blur.clamp(0.0, 20.0);
  }

  ThemeData getThemeData() {
    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: hasCustomBackground
          ? Colors.transparent
          : const Color(0xFF0A0E27),
      colorScheme: ColorScheme.dark(
        primary: _settings.primaryColor,
        secondary: _settings.secondaryColor,
        surface: _settings.accentColor,
      ),
    );
  }

  Future<void> setCustomColors({
    Color? primary,
    Color? secondary,
    Color? accent,
  }) async {
    if (primary != null) _settings.primaryColor = primary;
    if (secondary != null) _settings.secondaryColor = secondary;
    if (accent != null) _settings.accentColor = accent;
    await saveTheme();
  }

  Future<void> setBackground(String? path) async {
    _settings.backgroundImagePath = path;
    await saveTheme();
  }

  Future<void> setBackgroundOpacity(double opacity) async {
    _settings.backgroundOpacity = opacity.clamp(0.0, 1.0);
    await saveTheme();
  }

  Future<void> setBlurIntensity(double intensity) async {
    _settings.blurIntensity = intensity.clamp(0.0, 20.0);
    await saveTheme();
  }

  Future<void> setPrimaryColor(Color color) async {
    _settings.primaryColor = color;
    await saveTheme();
  }

  Future<void> setAccentColor(Color color) async {
    _settings.accentColor = color;
    await saveTheme();
  }

  @override
  void dispose() {
    super.dispose();
  }
}