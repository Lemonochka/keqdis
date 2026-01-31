import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:file_picker/file_picker.dart';
import 'unified_storage.dart';

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

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeSettings _settings = ThemeSettings();
  ThemeSettings get settings => _settings;

  bool get hasCustomBackground => _settings.backgroundImagePath != null;

  // БЕЗОПАСНОСТЬ: Максимальный размер изображения (10 MB)
  static const int _maxImageSize = 10 * 1024 * 1024;

  /// БЕЗОПАСНОСТЬ: Валидация типа файла
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

      // Проверяем существование файла фона
      if (newSettings.backgroundImagePath != null) {
        final bgFile = File(newSettings.backgroundImagePath!);
        if (!await bgFile.exists()) {
          newSettings.backgroundImagePath = null;
        } else {
          // БЕЗОПАСНОСТЬ: Проверка размера существующего файла
          final fileSize = await bgFile.length();
          if (fileSize > _maxImageSize) {
            print('Предупреждение: файл фона слишком большой, удаляем');
            await bgFile.delete();
            newSettings.backgroundImagePath = null;
          }
        }
      }

      _settings = newSettings;
      notifyListeners();
    } catch (e) {
      print('Ошибка загрузки темы: $e');
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
      print('Ошибка сохранения темы: $e');
    }
  }

  /// ИСПРАВЛЕНО: Выбрать фоновое изображение с проверкой безопасности
  Future<void> pickBackgroundImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;
        final sourceFile = File(sourcePath);

        // БЕЗОПАСНОСТЬ: Проверка существования файла
        if (!await sourceFile.exists()) {
          throw Exception('Файл не найден');
        }

        // БЕЗОПАСНОСТЬ: Проверка типа файла
        if (!_isValidImageExtension(sourcePath)) {
          throw Exception('Недопустимый формат изображения. Разрешены: JPG, PNG, WEBP, BMP');
        }

        // БЕЗОПАСНОСТЬ: Проверка размера файла
        final fileSize = await sourceFile.length();
        if (fileSize > _maxImageSize) {
          throw Exception('Файл слишком большой. Максимальный размер: ${_maxImageSize ~/ (1024 * 1024)} MB');
        }

        // БЕЗОПАСНОСТЬ: Проверка, что это действительно изображение
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
            print('Ошибка удаления старого фона: $e');
          }
        }

        // Копируем новое изображение
        await sourceFile.copy(destPath);

        // БЕЗОПАСНОСТЬ: Устанавливаем права доступа
        if (Platform.isWindows) {
          try {
            await Process.run('icacls', [
              destPath,
              '/inheritance:r',
              '/grant:r',
              '${Platform.environment['USERNAME']}:R'
            ]);
          } catch (e) {
            print('Предупреждение: не удалось установить ACL: $e');
          }
        }

        // Извлекаем цвета
        await _extractColorsFromImage(destPath);

        _settings.backgroundImagePath = destPath;
        await saveTheme();
      }
    } catch (e) {
      print('Ошибка выбора изображения: $e');
      rethrow;
    }
  }

  /// ОПТИМИЗИРОВАННОЕ извлечение цветов из изображения
  Future<void> _extractColorsFromImage(String imagePath) async {
    ui.Image? image;

    try {
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();

      // БЕЗОПАСНОСТЬ: Дополнительная проверка размера
      if (imageBytes.length > _maxImageSize) {
        throw Exception('Изображение слишком большое');
      }

      // Сжимаем изображение перед анализом
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 200,
        targetHeight: 200,
      );

      final frame = await codec.getNextFrame();
      image = frame.image;

      // Уменьшаем maximumColorCount для производительности
      final paletteGenerator = await PaletteGenerator.fromImage(
        image,
        maximumColorCount: 16,
      );

      // Получаем цвета
      final vibrant = paletteGenerator.vibrantColor?.color;
      final darkVibrant = paletteGenerator.darkVibrantColor?.color;
      final lightVibrant = paletteGenerator.lightVibrantColor?.color;
      final muted = paletteGenerator.mutedColor?.color;
      final darkMuted = paletteGenerator.darkMutedColor?.color;
      final lightMuted = paletteGenerator.lightMutedColor?.color;
      final dominant = paletteGenerator.dominantColor?.color;

      // PRIMARY COLOR
      _settings.primaryColor = vibrant ??
          lightVibrant ??
          dominant ??
          muted ??
          const Color(0xFF6C63FF);

      // SECONDARY COLOR
      _settings.secondaryColor = lightVibrant ??
          vibrant?.withOpacity(0.8) ??
          lightMuted ??
          _brightenColor(_settings.primaryColor, 0.3) ??
          const Color(0xFF00D9FF);

      // ACCENT COLOR
      _settings.accentColor = darkVibrant ??
          darkMuted ??
          _darkenColor(dominant ?? _settings.primaryColor, 0.7) ??
          const Color(0xFF1A1F3A);

      // Коррекция
      _settings.accentColor = _ensureContrast(_settings.accentColor);
      _settings.primaryColor = _ensureSaturation(_settings.primaryColor);
      _settings.secondaryColor = _ensureBrightness(_settings.secondaryColor);

    } catch (e) {
      print('Ошибка извлечения цветов: $e');

      // Используем цвета по умолчанию
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);
    } finally {
      // Освобождаем ресурсы изображения
      image?.dispose();
    }
  }

  /// Затемнить цвет
  Color? _darkenColor(Color color, double factor) {
    try {
      final hsl = HSLColor.fromColor(color);
      final darkened = hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0));
      return darkened.toColor();
    } catch (e) {
      return null;
    }
  }

  /// Осветлить цвет
  Color? _brightenColor(Color color, double factor) {
    try {
      final hsl = HSLColor.fromColor(color);
      final lightness = (hsl.lightness + (1.0 - hsl.lightness) * factor).clamp(0.0, 1.0);
      final brightened = hsl.withLightness(lightness);
      return brightened.toColor();
    } catch (e) {
      return null;
    }
  }

  /// Обеспечить контрастность
  Color _ensureContrast(Color color) {
    final hsl = HSLColor.fromColor(color);

    if (hsl.lightness > 0.3) {
      return hsl.withLightness(0.15).toColor();
    }

    return color;
  }

  /// Обеспечить насыщенность
  Color _ensureSaturation(Color color) {
    final hsl = HSLColor.fromColor(color);

    if (hsl.saturation < 0.5) {
      return hsl.withSaturation(0.7).toColor();
    }

    return color;
  }

  /// Обеспечить яркость
  Color _ensureBrightness(Color color) {
    final hsl = HSLColor.fromColor(color);

    if (hsl.lightness < 0.5) {
      return hsl.withLightness(0.6).toColor();
    }

    return color;
  }

  /// Удалить фоновое изображение
  Future<void> removeBackground() async {
    if (_settings.backgroundImagePath != null) {
      try {
        final file = File(_settings.backgroundImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Ошибка удаления фона: $e');
      }

      _settings.backgroundImagePath = null;

      // Возвращаем дефолтные цвета
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);

      await saveTheme();
    }
  }

  /// Обновить прозрачность фона
  void updateOpacity(double opacity) {
    _settings.backgroundOpacity = opacity.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Обновить размытие фона
  void updateBlur(double blur) {
    _settings.blurIntensity = blur.clamp(0.0, 20.0);
    notifyListeners();
  }

  /// Получить ThemeData для приложения
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

  /// Установить пользовательские цвета
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

  @override
  void dispose() {
    super.dispose();
  }
}