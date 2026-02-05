import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:image/image.dart' as img;

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

  static const int _maxImageSize = 10 * 1024 * 1024; // 10MB

  // НОВОЕ: Максимальное разрешение для фона (Full HD)
  static const int _maxWidth = 1920;
  static const int _maxHeight = 1080;

  static bool _isValidImageExtension(String path) {
    final extension = path.toLowerCase().split('.').last;
    const validExtensions = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};
    return validExtensions.contains(extension);
  }

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
      debugPrint('Ошибка загрузки темы: $e');
    }
  }

  Future<void> saveTheme() async {
    try {
      final filePath = await PortableStorage.getFilePath('theme.json');
      final file = File(filePath);
      final themeJson = JsonEncoder().convert(_settings.toJson());
      await file.writeAsString(themeJson);
      notifyListeners();
    } catch (e) {
      debugPrint('Ошибка сохранения темы: $e');
    }
  }

  // НОВОЕ: Сжатие изображения до Full HD
  Future<Uint8List> _resizeImageToFullHD(Uint8List imageBytes) async {
    try {
      // Декодируем изображение
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Не удалось декодировать изображение');
      }

      debugPrint('Оригинальный размер: ${image.width}x${image.height}');

      // Проверяем, нужно ли сжимать
      if (image.width <= _maxWidth && image.height <= _maxHeight) {
        debugPrint('Изображение уже подходящего размера, сжатие не требуется');
        return imageBytes;
      }

      // Вычисляем новые размеры с сохранением пропорций
      double aspectRatio = image.width / image.height;
      int newWidth, newHeight;

      if (aspectRatio > (_maxWidth / _maxHeight)) {
        // Ограничиваем по ширине
        newWidth = _maxWidth;
        newHeight = (_maxWidth / aspectRatio).round();
      } else {
        // Ограничиваем по высоте
        newHeight = _maxHeight;
        newWidth = (_maxHeight * aspectRatio).round();
      }

      debugPrint('Новый размер: ${newWidth}x${newHeight}');

      // Изменяем размер с использованием высококачественного алгоритма
      img.Image resized = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );

      // Кодируем обратно в JPEG с хорошим качеством (85%)
      final resizedBytes = Uint8List.fromList(
          img.encodeJpg(resized, quality: 85)
      );

      debugPrint('Размер файла уменьшен с ${imageBytes.length} до ${resizedBytes.length} байт');

      return resizedBytes;
    } catch (e) {
      debugPrint('Ошибка сжатия изображения: $e');
      // В случае ошибки возвращаем оригинал
      return imageBytes;
    }
  }

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

        final bytes = await sourceFile.readAsBytes();

        // Проверка валидности изображения
        try {
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: 10, targetHeight: 10);
          final frame = await codec.getNextFrame();
          frame.image.dispose();
          codec.dispose();
        } catch (e) {
          throw Exception('Файл не является корректным изображением');
        }

        // НОВОЕ: Сжимаем изображение до Full HD
        debugPrint('Сжатие изображения до Full HD...');
        final resizedBytes = await _resizeImageToFullHD(bytes);

        final portableDir = await PortableStorage.getPortableDirectory();

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        // Всегда сохраняем как JPEG после сжатия
        final fileName = 'custom_background_$timestamp.jpg';
        final destPath = '$portableDir/$fileName';

        // Удаляем старое изображение
        if (_settings.backgroundImagePath != null) {
          try {
            final oldFile = File(_settings.backgroundImagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
            }
          } catch (e) {
            debugPrint('Ошибка удаления старого фона: $e');
          }
        }

        // Копируем сжатое изображение
        await File(destPath).writeAsBytes(resizedBytes);

        if (Platform.isWindows) {
          try {
            await Process.run('icacls', [
              destPath,
              '/inheritance:r',
              '/grant:r',
              '${Platform.environment['USERNAME']}:R'
            ]);
          } catch (e) {
            debugPrint('Ошибка установки прав: $e');
          }
        }

        // Извлекаем цвета УЛУЧШЕННЫМ алгоритмом
        await _extractColorsFromImage(resizedBytes);

        _settings.backgroundImagePath = destPath;
        await saveTheme();
      }
    } catch (e) {
      rethrow;
    }
  }

  // ЗНАЧИТЕЛЬНО УЛУЧШЕННЫЙ алгоритм извлечения цветов
  Future<void> _extractColorsFromImage(Uint8List imageBytes) async {
    ui.Image? image;
    ui.Codec? codec;

    try {
      if (imageBytes.length > _maxImageSize) {
        throw Exception('Изображение слишком большое');
      }

      // ОПТИМИЗАЦИЯ: Используем очень маленький размер для анализа
      codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 80,  // Увеличено с 50 для лучшего качества анализа
        targetHeight: 80,
      );

      final frame = await codec.getNextFrame();
      image = frame.image;

      // Генерация палитры с большим количеством цветов для лучшего анализа
      final paletteGenerator = await PaletteGenerator.fromImage(
        image,
        maximumColorCount: 20, // Увеличено с 8
      );

      // УЛУЧШЕННЫЙ алгоритм подбора цветов
      _settings.primaryColor = _selectPrimaryColorImproved(paletteGenerator);
      _settings.secondaryColor = _selectSecondaryColorImproved(paletteGenerator, _settings.primaryColor);
      _settings.accentColor = _selectAccentColorImproved(paletteGenerator);

    } catch (e) {
      debugPrint('Ошибка извлечения цветов: $e');
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  // НОВЫЙ: Улучшенный алгоритм выбора primary цвета
  Color _selectPrimaryColorImproved(PaletteGenerator palette) {
    // Пробуем найти яркий насыщенный цвет
    final candidates = [
      palette.vibrantColor?.color,
      palette.lightVibrantColor?.color,
      palette.dominantColor?.color,
    ];

    for (var candidate in candidates) {
      if (candidate == null) continue;

      final hsl = HSLColor.fromColor(candidate);

      // Ищем цвет с хорошей насыщенностью и яркостью
      if (hsl.saturation > 0.4 && hsl.lightness > 0.3 && hsl.lightness < 0.8) {
        return hsl
            .withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0))
            .withLightness(0.55)
            .toColor();
      }
    }

    // Если не нашли подходящий, возвращаем модифицированный dominant
    if (palette.dominantColor != null) {
      final hsl = HSLColor.fromColor(palette.dominantColor!.color);
      return hsl
          .withSaturation(0.7)
          .withLightness(0.55)
          .toColor();
    }

    return const Color(0xFF6C63FF);
  }

  // НОВЫЙ: Улучшенный алгоритм выбора secondary цвета
  Color _selectSecondaryColorImproved(PaletteGenerator palette, Color primary) {
    final primaryHsl = HSLColor.fromColor(primary);

    // Ищем цвет с отличающимся оттенком
    final candidates = [
      palette.lightVibrantColor?.color,
      palette.vibrantColor?.color,
      palette.lightMutedColor?.color,
    ];

    for (var candidate in candidates) {
      if (candidate == null) continue;

      final hsl = HSLColor.fromColor(candidate);

      // Проверяем, что оттенок достаточно отличается
      final hueDiff = (hsl.hue - primaryHsl.hue).abs();
      if (hueDiff > 30 && hueDiff < 330) { // Не слишком близко и не противоположный
        return hsl
            .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
            .withLightness(0.6)
            .toColor();
      }
    }

    // Если не нашли подходящий, создаем комплементарный к primary
    return primaryHsl
        .withHue((primaryHsl.hue + 120) % 360) // Триадный цвет
        .withSaturation(0.65)
        .withLightness(0.6)
        .toColor();
  }

  // НОВЫЙ: Улучшенный алгоритм выбора accent цвета
  Color _selectAccentColorImproved(PaletteGenerator palette) {
    // Ищем темный приглушенный цвет для фона
    final candidates = [
      palette.darkMutedColor?.color,
      palette.darkVibrantColor?.color,
      palette.mutedColor?.color,
    ];

    for (var candidate in candidates) {
      if (candidate == null) continue;

      final hsl = HSLColor.fromColor(candidate);

      // Хотим темный цвет с низкой насыщенностью
      if (hsl.lightness < 0.3) {
        return hsl
            .withSaturation((hsl.saturation * 0.4).clamp(0.0, 1.0))
            .withLightness(0.11)
            .toColor();
      }
    }

    // Если не нашли, используем dominant но делаем очень темным
    if (palette.dominantColor != null) {
      final hsl = HSLColor.fromColor(palette.dominantColor!.color);
      return hsl
          .withSaturation(0.25)
          .withLightness(0.11)
          .toColor();
    }

    return const Color(0xFF1A1F3A);
  }

  Future<void> removeBackground() async {
    if (_settings.backgroundImagePath != null) {
      try {
        final file = File(_settings.backgroundImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Ошибка удаления фона: $e');
      }

      _settings.backgroundImagePath = null;
      _settings.primaryColor = const Color(0xFF6C63FF);
      _settings.secondaryColor = const Color(0xFF00D9FF);
      _settings.accentColor = const Color(0xFF1A1F3A);

      await saveTheme();
    }
  }

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