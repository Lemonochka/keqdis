import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:image/image.dart' as img;

class _AppColors {
  // Светлая тема
  static const lightPrimary      = Color(0xFFD63F6A);
  static const lightSecondary    = Color(0xFFBF2D55);
  static const lightAccent       = Color(0xFFF5E6EA);
  static const lightBackground   = Color(0xFFD9A8B5);
  static const lightSidebar      = Color(0xFFC4899A);
  static const lightNavIndicator = Color(0xFFE8C0CC);
  static const lightText         = Color(0xFF1A1A1A);
  static const lightSecText      = Color(0xFF5C3040);
  static const lightBorder       = Color(0x60D63F6A);

  // Тёмная тема
  static const darkPrimary      = Color(0xFFFF8FAB);
  static const darkSecondary    = Color(0xFFFF6B8A);
  static const darkAccent       = Color(0xFF2D1A1A);
  static const darkBackground   = Color(0xFF1A0D0D);
  static const darkSidebar      = Color(0xFF200D0D);
  static const darkNavIndicator = Color(0xFF3D1A1A);
  static const darkText         = Color(0xFFF5E6E6);
  static const darkSecText      = Color(0xFF9E7A7A);
  static const darkBorder       = Color(0x12FFFFFF);

  // Общие
  static const activeNav   = Color(0xFFFF6B8A);
  static const inactiveNav = Color(0xFF9E7A7A);
  static const wave        = Color(0xFF4CAF93);
  static const powerBtn    = Color(0xFFFFB3C1);
  static const powerGlow   = Color(0xFFFF96AA);
  static const fab         = Color(0xFFFF8FAB);

  static const protoBgLight   = Color(0xFFE8D5FF);
  static const protoTextLight  = Color(0xFF8B5CF6);
  static const protoBgDark    = Color(0xFF3D2060);
  static const protoTextDark   = Color(0xFFC4A0FF);
}

class ThemeSettings {
  String? backgroundImagePath;
  Color primaryColor;
  Color secondaryColor;
  Color accentColor;
  double backgroundOpacity;
  double blurIntensity;
  bool isDarkMode;

  ThemeSettings({
    this.backgroundImagePath,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    this.backgroundOpacity = 0.3,
    this.blurIntensity = 10.0,
    this.isDarkMode = false,
  })  : primaryColor  = primaryColor  ?? _AppColors.lightPrimary,
        secondaryColor = secondaryColor ?? _AppColors.lightSecondary,
        accentColor   = accentColor   ?? _AppColors.lightAccent;

  bool get isGlassmorphism => backgroundImagePath != null;

  Color get textColor {
    if (isGlassmorphism) return Colors.white;
    return isDarkMode ? _AppColors.darkText : _AppColors.lightText;
  }

  Color get secondaryTextColor {
    if (isGlassmorphism) return Colors.white.withOpacity(0.65);
    return isDarkMode ? _AppColors.darkSecText : _AppColors.lightSecText;
  }

  Color get backgroundColor {
    if (isGlassmorphism) return Colors.transparent;
    return isDarkMode ? _AppColors.darkBackground : _AppColors.lightBackground;
  }

  Color get cardColor {
    if (isGlassmorphism) return Colors.black.withOpacity(0.42);
    return isDarkMode ? const Color(0xFF2A1515) : const Color(0xFFF5E6EA);
  }

  Color get sidebarColor {
    if (isGlassmorphism) return Colors.transparent;
    return isDarkMode ? _AppColors.darkSidebar : _AppColors.lightSidebar;
  }

  Color get navIndicatorColor {
    if (isGlassmorphism) return Colors.white.withOpacity(0.18);
    return isDarkMode ? _AppColors.darkNavIndicator : _AppColors.lightNavIndicator;
  }

  Color get borderColor {
    if (isGlassmorphism) return Colors.white.withOpacity(0.14);
    return isDarkMode ? _AppColors.darkBorder : _AppColors.lightBorder;
  }

  Color get searchBarColor {
    if (isGlassmorphism) return Colors.black.withOpacity(0.38);
    return isDarkMode ? const Color(0xFF2A1515) : _AppColors.lightAccent;
  }

  Color get fabColor           => isDarkMode ? _AppColors.darkSecondary : _AppColors.fab;
  Color get protocolBadgeBg    => isDarkMode ? _AppColors.protoBgDark   : _AppColors.protoBgLight;
  Color get protocolBadgeText  => isDarkMode ? _AppColors.protoTextDark : _AppColors.protoTextLight;
  Color get powerButtonColor   => _AppColors.powerBtn;
  Color get powerButtonGlow    => _AppColors.powerGlow;

  static const Color waveColor        = _AppColors.wave;
  static const Color activeNavColor   = _AppColors.activeNav;
  static const Color inactiveNavColor = _AppColors.inactiveNav;

  Map<String, dynamic> toJson() => {
    'backgroundImagePath': backgroundImagePath,
    'primaryColor':        primaryColor.value,
    'secondaryColor':      secondaryColor.value,
    'accentColor':         accentColor.value,
    'backgroundOpacity':   backgroundOpacity,
    'blurIntensity':       blurIntensity,
    'isDarkMode':          isDarkMode,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    final dark = json['isDarkMode'] as bool? ?? false;
    return ThemeSettings(
      backgroundImagePath: json['backgroundImagePath'] as String?,
      primaryColor:  json['primaryColor']  != null ? Color(json['primaryColor'] as int)  : null,
      secondaryColor: json['secondaryColor'] != null ? Color(json['secondaryColor'] as int) : null,
      accentColor:   json['accentColor']   != null ? Color(json['accentColor'] as int)   : null,
      backgroundOpacity: (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.3,
      blurIntensity:    (json['blurIntensity'] as num?)?.toDouble() ?? 10.0,
      isDarkMode:        dark,
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

  static const int _maxImageSize = 10 * 1024 * 1024; // 10 MB
  static const int _maxWidth     = 1920;
  static const int _maxHeight    = 1080;

  static bool _isValidImageExtension(String path) {
    final ext = path.toLowerCase().split('.').last;
    return {'jpg', 'jpeg', 'png', 'webp', 'bmp'}.contains(ext);
  }

  Future<void> loadTheme() async {
    try {
      await PortableStorage.getPortableDirectory();
      final file = File(PortableStorage.getFilePath('theme.json'));
      if (!await file.exists()) return;

      final decoded = Map<String, dynamic>.from(
        const JsonDecoder().convert(await file.readAsString()),
      );
      final newSettings = ThemeSettings.fromJson(decoded);

      if (newSettings.backgroundImagePath != null) {
        final bgFile = File(newSettings.backgroundImagePath!);
        if (!await bgFile.exists() || await bgFile.length() > _maxImageSize) {
          try { await bgFile.delete(); } catch (_) {}
          newSettings.backgroundImagePath = null;
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
      await PortableStorage.getPortableDirectory();
      final file = File(PortableStorage.getFilePath('theme.json'));
      await file.writeAsString(const JsonEncoder().convert(_settings.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('Ошибка сохранения темы: $e');
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    _settings.isDarkMode = isDark;
    if (!hasCustomBackground) {
      _settings.primaryColor   = isDark ? _AppColors.darkPrimary   : _AppColors.lightPrimary;
      _settings.secondaryColor = isDark ? _AppColors.darkSecondary  : _AppColors.lightSecondary;
      _settings.accentColor    = isDark ? _AppColors.darkAccent     : _AppColors.lightAccent;
    }
    await saveTheme();
  }

  void toggleDarkMode() => setDarkMode(!_settings.isDarkMode);

  ThemeData getThemeData() {
    final dark   = _settings.isDarkMode;
    final bgColor = hasCustomBackground
        ? Colors.transparent
        : _settings.backgroundColor;

    final colorScheme = dark
        ? ColorScheme.fromSeed(
      seedColor:  _AppColors.darkPrimary,
      brightness: Brightness.dark,
    ).copyWith(
      primary:    _AppColors.darkPrimary,
      secondary:  _AppColors.darkSecondary,
      surface:    _AppColors.darkAccent,
      background: _AppColors.darkBackground,
    )
        : ColorScheme.fromSeed(
      seedColor:  _AppColors.lightPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary:    _AppColors.lightPrimary,
      secondary:  _AppColors.lightSecondary,
      surface:    _AppColors.lightAccent,
      background: _AppColors.lightBackground,
    );

    return ThemeData(
      useMaterial3:           true,
      colorScheme:            colorScheme,
      scaffoldBackgroundColor: bgColor,
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dividerColor: dark ? _AppColors.darkBorder : _AppColors.lightBorder,
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected) ? _AppColors.lightPrimary : null),
        trackColor: MaterialStateProperty.resolveWith((s) =>
        s.contains(MaterialState.selected)
            ? _AppColors.lightPrimary.withOpacity(0.5)
            : null),
      ),
    );
  }

  Future<Uint8List> _resizeImageToFullHD(Uint8List imageBytes) async {
    try {
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('Не удалось декодировать изображение');

      if (image.width <= _maxWidth && image.height <= _maxHeight) return imageBytes;

      final ar = image.width / image.height;
      int newWidth, newHeight;
      if (ar > (_maxWidth / _maxHeight)) {
        newWidth  = _maxWidth;
        newHeight = (_maxWidth / ar).round();
      } else {
        newHeight = _maxHeight;
        newWidth  = (_maxHeight * ar).round();
      }

      final resized = img.copyResize(
        image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (e) {
      debugPrint('Ошибка сжатия: $e');
      return imageBytes;
    }
  }

  Future<void> pickBackgroundImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) return;

      final sourcePath = result.files.single.path!;
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) throw Exception('Файл не найден');
      if (!_isValidImageExtension(sourcePath)) {
        throw Exception('Недопустимый формат. Разрешены: JPG, PNG, WEBP, BMP');
      }

      final fileSize = await sourceFile.length();
      if (fileSize > _maxImageSize) {
        throw Exception('Файл слишком большой. Максимум: ${_maxImageSize ~/ (1024 * 1024)} МБ');
      }

      final bytes = await sourceFile.readAsBytes();

      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 10, targetHeight: 10);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();

      final resizedBytes  = await _resizeImageToFullHD(bytes);
      final portableDir   = await PortableStorage.getPortableDirectory();
      final timestamp     = DateTime.now().millisecondsSinceEpoch;
      final destPath      = '$portableDir/custom_background_$timestamp.jpg';

      if (_settings.backgroundImagePath != null) {
        try {
          final old = File(_settings.backgroundImagePath!);
          if (await old.exists()) await old.delete();
        } catch (_) {}
      }

      await File(destPath).writeAsBytes(resizedBytes);

      if (Platform.isWindows) {
        try {
          await Process.run('icacls', [
            destPath, '/inheritance:r', '/grant:r',
            '${Platform.environment['USERNAME']}:R',
          ]);
        } catch (_) {}
      }

      await _extractColorsFromImage(resizedBytes);
      _settings.backgroundImagePath = destPath;
      await saveTheme();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _extractColorsFromImage(Uint8List imageBytes) async {
    ui.Image? image;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 80, targetHeight: 80);
      final frame = await codec.getNextFrame();
      image = frame.image;

      final palette = await PaletteGenerator.fromImage(image, maximumColorCount: 20);

      _settings.primaryColor   = _selectPrimaryColorImproved(palette);
      _settings.secondaryColor = _selectSecondaryColorImproved(palette, _settings.primaryColor);
      _settings.accentColor    = _selectAccentColorImproved(palette);
    } catch (e) {
      debugPrint('Ошибка извлечения цветов: $e');
      _settings.primaryColor   = _AppColors.lightPrimary;
      _settings.secondaryColor = _AppColors.lightSecondary;
      _settings.accentColor    = _settings.isDarkMode ? _AppColors.darkAccent : _AppColors.lightAccent;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  Color _selectPrimaryColorImproved(PaletteGenerator palette) {
    for (final c in [palette.vibrantColor?.color, palette.lightVibrantColor?.color, palette.dominantColor?.color]) {
      if (c == null) continue;
      final hsl = HSLColor.fromColor(c);
      if (hsl.saturation > 0.4 && hsl.lightness > 0.3 && hsl.lightness < 0.8) {
        return hsl.withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0)).withLightness(0.55).toColor();
      }
    }
    if (palette.dominantColor != null) {
      final hsl = HSLColor.fromColor(palette.dominantColor!.color);
      return hsl.withSaturation(0.7).withLightness(0.55).toColor();
    }
    return _AppColors.lightPrimary;
  }

  Color _selectSecondaryColorImproved(PaletteGenerator palette, Color primary) {
    final primaryHsl = HSLColor.fromColor(primary);
    for (final c in [palette.lightVibrantColor?.color, palette.vibrantColor?.color, palette.lightMutedColor?.color]) {
      if (c == null) continue;
      final hsl = HSLColor.fromColor(c);
      final diff = (hsl.hue - primaryHsl.hue).abs();
      if (diff > 30 && diff < 330) {
        return hsl.withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0)).withLightness(0.6).toColor();
      }
    }
    return primaryHsl.withHue((primaryHsl.hue + 120) % 360).withSaturation(0.65).withLightness(0.6).toColor();
  }

  Color _selectAccentColorImproved(PaletteGenerator palette) {
    for (final c in [palette.darkMutedColor?.color, palette.darkVibrantColor?.color, palette.mutedColor?.color]) {
      if (c == null) continue;
      final hsl = HSLColor.fromColor(c);
      if (hsl.lightness < 0.3) {
        return hsl.withSaturation((hsl.saturation * 0.4).clamp(0.0, 1.0)).withLightness(0.11).toColor();
      }
    }
    if (palette.dominantColor != null) {
      return HSLColor.fromColor(palette.dominantColor!.color).withSaturation(0.25).withLightness(0.11).toColor();
    }
    return _settings.isDarkMode ? _AppColors.darkAccent : _AppColors.lightAccent;
  }

  Future<void> removeBackground() async {
    if (_settings.backgroundImagePath != null) {
      try {
        final f = File(_settings.backgroundImagePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _settings.backgroundImagePath = null;
    }
    final dark = _settings.isDarkMode;
    _settings.primaryColor   = dark ? _AppColors.darkPrimary   : _AppColors.lightPrimary;
    _settings.secondaryColor = dark ? _AppColors.darkSecondary  : _AppColors.lightSecondary;
    _settings.accentColor    = dark ? _AppColors.darkAccent     : _AppColors.lightAccent;
    await saveTheme();
  }

  void updateOpacity(double v) => _settings.backgroundOpacity = v.clamp(0.0, 1.0);
  void updateBlur(double v)    => _settings.blurIntensity = v.clamp(0.0, 20.0);

  Future<void> setCustomColors({Color? primary, Color? secondary, Color? accent}) async {
    if (primary  != null) _settings.primaryColor   = primary;
    if (secondary != null) _settings.secondaryColor = secondary;
    if (accent   != null) _settings.accentColor    = accent;
    await saveTheme();
  }

  Future<void> setBackground(String? path)         async => _settings.backgroundImagePath = path;
  Future<void> setBackgroundOpacity(double v)      async { _settings.backgroundOpacity = v.clamp(0.0, 1.0); await saveTheme(); }
  Future<void> setBlurIntensity(double v)          async { _settings.blurIntensity = v.clamp(0.0, 20.0); await saveTheme(); }
  Future<void> setPrimaryColor(Color color)        async { _settings.primaryColor = color;   await saveTheme(); }
  Future<void> setAccentColor(Color color)         async { _settings.accentColor  = color;   await saveTheme(); }

  @override
  void dispose() => super.dispose();
}