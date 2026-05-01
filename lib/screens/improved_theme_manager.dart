import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:keqdis/storages/unified_storage.dart';

class _AppColors {
  // Базовая унифицированная тема
  static const lightPrimary = Color(0xFFD63F6A);
  static const lightSecondary = Color(0xFFBF2D55);
  static const lightAccent = Color(0xFFF5E6EA);
  static const lightBackground = Color(0xFFD9A8B5);
  static const lightSidebar = Color(0xFFC4899A);
  static const lightNavIndicator = Color(0xFFE8C0CC);
  static const lightText = Color(0xFF1A1A1A);
  static const lightSecText = Color(0xFF5C3040);
  static const lightBorder = Color(0x60D63F6A);

  // Общие
  static const activeNav = Color(0xFFFF6B8A);
  static const inactiveNav = Color(0xFF9E7A7A);
  static const wave = Color(0xFF4CAF93);
  static const fab = Color(0xFFFF8FAB);

  static const protoBgLight = Color(0xFFE8D5FF);
  static const protoTextLight = Color(0xFF8B5CF6);
}

class ThemePreset {
  final String id;
  final String name;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color sidebar;
  final Color navIndicator;
  final Color text;
  final Color secondaryText;
  final Color border;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.sidebar,
    required this.navIndicator,
    required this.text,
    required this.secondaryText,
    required this.border,
  });
}

class ThemeSettings {
  String? backgroundImagePath;
  Color primaryColor;
  Color secondaryColor;
  Color accentColor;
  Color backgroundBaseColor;
  Color sidebarBaseColor;
  Color navIndicatorBaseColor;
  Color textBaseColor;
  Color secondaryTextBaseColor;
  Color borderBaseColor;
  double backgroundOpacity;
  double blurIntensity;
  bool isDarkMode;
  bool isDark;
  String presetId;

  ThemeSettings({
    this.backgroundImagePath,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? backgroundBaseColor,
    Color? sidebarBaseColor,
    Color? navIndicatorBaseColor,
    Color? textBaseColor,
    Color? secondaryTextBaseColor,
    Color? borderBaseColor,
    this.backgroundOpacity = 0.3,
    this.blurIntensity = 10.0,
    this.isDarkMode = false,
    this.isDark = false,
    this.presetId = 'ocean',
  }) : primaryColor = primaryColor ?? _AppColors.lightPrimary,
       secondaryColor = secondaryColor ?? _AppColors.lightSecondary,
       accentColor = accentColor ?? _AppColors.lightAccent,
       backgroundBaseColor = backgroundBaseColor ?? _AppColors.lightBackground,
       sidebarBaseColor = sidebarBaseColor ?? _AppColors.lightSidebar,
       navIndicatorBaseColor =
           navIndicatorBaseColor ?? _AppColors.lightNavIndicator,
       textBaseColor = textBaseColor ?? _AppColors.lightText,
       secondaryTextBaseColor =
           secondaryTextBaseColor ?? _AppColors.lightSecText,
       borderBaseColor = borderBaseColor ?? _AppColors.lightBorder;

  bool get isGlassmorphism => backgroundImagePath != null;

  Color get textColor {
    if (isGlassmorphism) {
      return const Color(0xFF111111);
    }
    return textBaseColor;
  }

  Color get secondaryTextColor {
    if (isGlassmorphism) {
      final base = const Color(0xFF111111);
      return base.withOpacity(0.70);
    }
    return secondaryTextBaseColor;
  }

  Color get backgroundColor {
    if (isGlassmorphism) return Colors.transparent;
    return backgroundBaseColor;
  }

  Color get cardColor {
    if (isGlassmorphism) return Colors.black.withOpacity(0.42);
    return accentColor;
  }

  Color get sidebarColor {
    // In glassmorphism mode we still need a readable surface for AppBars / side panels.
    if (isGlassmorphism) return Colors.black.withOpacity(0.22);
    return sidebarBaseColor;
  }

  Color get navIndicatorColor {
    if (isGlassmorphism) return Colors.white.withOpacity(0.18);
    return navIndicatorBaseColor;
  }

  Color get borderColor {
    if (isGlassmorphism) return Colors.white.withOpacity(0.14);
    return borderBaseColor;
  }

  Color get searchBarColor {
    if (isGlassmorphism) return Colors.black.withOpacity(0.38);
    return accentColor;
  }

  Color get fabColor => _AppColors.fab;
  Color get protocolBadgeBg => _AppColors.protoBgLight;
  Color get protocolBadgeText => _AppColors.protoTextLight;
  Color get powerButtonColor =>
      Color.lerp(primaryColor, accentColor, 0.35) ?? primaryColor;
  Color get powerButtonGlow => primaryColor;

  static const Color waveColor = _AppColors.wave;
  static const Color activeNavColor = _AppColors.activeNav;
  static const Color inactiveNavColor = _AppColors.inactiveNav;

  Map<String, dynamic> toJson() => {
    'backgroundImagePath': backgroundImagePath,
    'primaryColor': primaryColor.value,
    'secondaryColor': secondaryColor.value,
    'accentColor': accentColor.value,
    'backgroundBaseColor': backgroundBaseColor.value,
    'sidebarBaseColor': sidebarBaseColor.value,
    'navIndicatorBaseColor': navIndicatorBaseColor.value,
    'textBaseColor': textBaseColor.value,
    'secondaryTextBaseColor': secondaryTextBaseColor.value,
    'borderBaseColor': borderBaseColor.value,
    'backgroundOpacity': backgroundOpacity,
    'blurIntensity': blurIntensity,
    'isDarkMode': isDarkMode,
    'isDark': isDark,
    'presetId': presetId,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      backgroundImagePath: json['backgroundImagePath'] as String?,
      primaryColor: json['primaryColor'] != null
          ? Color(json['primaryColor'] as int)
          : null,
      secondaryColor: json['secondaryColor'] != null
          ? Color(json['secondaryColor'] as int)
          : null,
      accentColor: json['accentColor'] != null
          ? Color(json['accentColor'] as int)
          : null,
      backgroundBaseColor: json['backgroundBaseColor'] != null
          ? Color(json['backgroundBaseColor'] as int)
          : null,
      sidebarBaseColor: json['sidebarBaseColor'] != null
          ? Color(json['sidebarBaseColor'] as int)
          : null,
      navIndicatorBaseColor: json['navIndicatorBaseColor'] != null
          ? Color(json['navIndicatorBaseColor'] as int)
          : null,
      textBaseColor: json['textBaseColor'] != null
          ? Color(json['textBaseColor'] as int)
          : null,
      secondaryTextBaseColor: json['secondaryTextBaseColor'] != null
          ? Color(json['secondaryTextBaseColor'] as int)
          : null,
      borderBaseColor: json['borderBaseColor'] != null
          ? Color(json['borderBaseColor'] as int)
          : null,
      backgroundOpacity: (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.3,
      blurIntensity: (json['blurIntensity'] as num?)?.toDouble() ?? 10.0,
      isDarkMode: false,
      isDark: json['isDark'] as bool? ?? false,
      presetId: json['presetId'] as String? ?? 'ocean',
    );
  }
}

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeSettings _settings = ThemeSettings();
  ThemeSettings get settings => _settings;
  List<ThemePreset> get presets => _presets;

  static const List<ThemePreset> _presets = [
    // Light themes
    ThemePreset(
      id: 'ocean',
      name: 'Ocean',
      primary: Color(0xFF2B6CF2),
      secondary: Color(0xFF1E55C2),
      accent: Color(0xFFE9F2FF),
      background: Color(0xFFC7DCF7),
      sidebar: Color(0xFFB4CCEA),
      navIndicator: Color(0xFFDCEAFF),
      text: Color(0xFF102540),
      secondaryText: Color(0xFF2E4C70),
      border: Color(0x552B6CF2),
    ),
    ThemePreset(
      id: 'forest',
      name: 'Forest',
      primary: Color(0xFF2E8B57),
      secondary: Color(0xFF1F6B41),
      accent: Color(0xFFEAF6EE),
      background: Color(0xFFC9E4D1),
      sidebar: Color(0xFFB3D5BF),
      navIndicator: Color(0xFFD7EEDC),
      text: Color(0xFF143021),
      secondaryText: Color(0xFF2D5940),
      border: Color(0x552E8B57),
    ),
    ThemePreset(
      id: 'violet',
      name: 'Violet',
      primary: Color(0xFF7A3FE2),
      secondary: Color(0xFF5E2DB6),
      accent: Color(0xFFF1EAFE),
      background: Color(0xFFD7C6F2),
      sidebar: Color(0xFFC4AFE8),
      navIndicator: Color(0xFFE5D7FA),
      text: Color(0xFF271444),
      secondaryText: Color(0xFF4B2F73),
      border: Color(0x557A3FE2),
    ),
    ThemePreset(
      id: 'mono',
      name: 'Monochrome',
      primary: Color(0xFF4B5563),
      secondary: Color(0xFF374151),
      accent: Color(0xFFF3F4F6),
      background: Color(0xFFE5E7EB),
      sidebar: Color(0xFFD7DBE2),
      navIndicator: Color(0xFFE6E9EF),
      text: Color(0xFF111827),
      secondaryText: Color(0xFF4B5563),
      border: Color(0x554B5563),
    ),
    // Dark themes
    ThemePreset(
      id: 'ocean_dark',
      name: 'Ocean Dark',
      primary: Color(0xFF4A8FFF),
      secondary: Color(0xFF2B6CF2),
      accent: Color(0xFF1A2D4A),
      background: Color(0xFF0F1B2D),
      sidebar: Color(0xFF141F32),
      navIndicator: Color(0xFF1E2D45),
      text: Color(0xFFE8F0FF),
      secondaryText: Color(0xFF8BA4CC),
      border: Color(0x404A8FFF),
    ),
    ThemePreset(
      id: 'forest_dark',
      name: 'Forest Dark',
      primary: Color(0xFF4CAF6A),
      secondary: Color(0xFF2E8B57),
      accent: Color(0xFF1A2D1F),
      background: Color(0xFF0F1F14),
      sidebar: Color(0xFF142418),
      navIndicator: Color(0xFF1A2D1E),
      text: Color(0xFFE8F5EC),
      secondaryText: Color(0xFF8BCC9E),
      border: Color(0x404CAF6A),
    ),
    ThemePreset(
      id: 'violet_dark',
      name: 'Violet Dark',
      primary: Color(0xFF9B6FFF),
      secondary: Color(0xFF7A3FE2),
      accent: Color(0xFF2A1A44),
      background: Color(0xFF1A0F2D),
      sidebar: Color(0xFF1F142E),
      navIndicator: Color(0xFF251A3A),
      text: Color(0xFFEEDFFF),
      secondaryText: Color(0xFFAA8FCC),
      border: Color(0x409B6FFF),
    ),
    ThemePreset(
      id: 'mono_dark',
      name: 'Mono Dark',
      primary: Color(0xFF6B7280),
      secondary: Color(0xFF4B5563),
      accent: Color(0xFF1F2328),
      background: Color(0xFF111827),
      sidebar: Color(0xFF141A22),
      navIndicator: Color(0xFF1A2028),
      text: Color(0xFFE5E7EB),
      secondaryText: Color(0xFF9CA3AF),
      border: Color(0x406B7280),
    ),
  ];

  bool get hasCustomBackground => false;

  Future<void> loadTheme() async {
    try {
      await PortableStorage.getPortableDirectory();
      final file = File(PortableStorage.getFilePath('theme.json'));
      if (!await file.exists()) {
        // First run: apply the first custom preset instead of legacy pink defaults.
        _applyPresetToSettings(_settings, _presets.first);
        await saveTheme();
        return;
      }

      final decoded = Map<String, dynamic>.from(
        const JsonDecoder().convert(await file.readAsString()),
      );
      final newSettings = ThemeSettings.fromJson(decoded);
      final legacyDarkMode = decoded['isDarkMode'] as bool? ?? false;
      final preset = _presetById(newSettings.presetId) ?? _presets.first;
      newSettings.isDarkMode = false;
      if (legacyDarkMode) {
        _applyPresetToSettings(newSettings, _presets.first);
      }
      if (newSettings.backgroundBaseColor == _AppColors.lightBackground &&
          newSettings.sidebarBaseColor == _AppColors.lightSidebar &&
          newSettings.navIndicatorBaseColor == _AppColors.lightNavIndicator &&
          newSettings.textBaseColor == _AppColors.lightText &&
          newSettings.secondaryTextBaseColor == _AppColors.lightSecText &&
          newSettings.borderBaseColor == _AppColors.lightBorder &&
          newSettings.primaryColor == _AppColors.lightPrimary &&
          newSettings.secondaryColor == _AppColors.lightSecondary &&
          newSettings.accentColor == _AppColors.lightAccent) {
        _applyPresetToSettings(newSettings, preset);
      }

      if (newSettings.backgroundImagePath != null) {
        try {
          final bgFile = File(newSettings.backgroundImagePath!);
          if (await bgFile.exists()) await bgFile.delete();
        } catch (_) {}
      }
      newSettings.backgroundImagePath = null;

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
    _settings.isDark = isDark;
    _settings.isDarkMode = false;
    
    // Apply corresponding dark/light preset
    final presetId = _settings.presetId;
    String newPresetId;
    if (isDark) {
      // If already dark variant, keep it
      if (presetId.endsWith('_dark')) {
        newPresetId = presetId;
      } else {
        // Find corresponding dark variant
        newPresetId = '${presetId}_dark';
        final darkPreset = _presetById(newPresetId);
        if (darkPreset == null) {
          // No dark variant, use default dark
          newPresetId = '${_presets.first.id}_dark';
        }
      }
    } else {
      // Remove _dark suffix to get light variant
      if (presetId.endsWith('_dark')) {
        newPresetId = presetId.substring(0, presetId.length - 5);
      } else {
        newPresetId = presetId;
      }
    }
    
    final preset = _presetById(newPresetId);
    if (preset != null) {
      _applyPresetToSettings(_settings, preset);
    }
    
    await saveTheme();
  }

  void toggleDarkMode() => setDarkMode(!_settings.isDark);

  ThemeData getThemeData() {
    final brightness = _settings.isDark ? Brightness.dark : Brightness.light;

    // When glassmorphism background is enabled, the "real" background is drawn
    // by the page, so the Scaffold should stay transparent.
    final scaffoldBg = hasCustomBackground
        ? Colors.transparent
        : _settings.backgroundColor;

    final seed = _settings.primaryColor;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: _settings.primaryColor,
          secondary: _settings.secondaryColor,
          surface: _settings.accentColor,
          // Keep background aligned with your custom theme model.
          surfaceTint: _settings.primaryColor,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      visualDensity: VisualDensity.standard,
    );

    // Material 3 "Expressive" feel: rounder shapes, calmer elevations,
    // consistent component theming, and better default typography.
    final radius = BorderRadius.circular(16);

    return base.copyWith(
      dividerTheme: DividerThemeData(
        color: _settings.borderColor,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: hasCustomBackground
            ? Colors.black.withOpacity(0.22)
            : scheme.surface,
        foregroundColor: _settings.textColor,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: _settings.textColor,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _settings.cardColor,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: hasCustomBackground
            ? Colors.transparent
            : scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _settings.cardColor.withOpacity(0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _settings.borderColor),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: _settings.textColor,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: _settings.borderColor),
          textStyle: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          foregroundColor: scheme.primary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _settings.searchBarColor,
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: _settings.secondaryTextColor,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _settings.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _settings.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withOpacity(0.45)
              : null,
        ),
      ),
    );
  }

  Future<void> pickBackgroundImage() async {
    // Feature removed intentionally.
    if (_settings.backgroundImagePath != null) {
      await removeBackground();
    }
  }

  Future<void> removeBackground() async {
    if (_settings.backgroundImagePath != null) {
      try {
        final f = File(_settings.backgroundImagePath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _settings.backgroundImagePath = null;
    }
    final preset = _presetById(_settings.presetId) ?? _presets.first;
    _applyPresetToSettings(_settings, preset);
    await saveTheme();
  }

  void updateOpacity(double v) =>
      _settings.backgroundOpacity = v.clamp(0.0, 1.0);
  void updateBlur(double v) => _settings.blurIntensity = v.clamp(0.0, 20.0);

  Future<void> setCustomColors({
    Color? primary,
    Color? secondary,
    Color? accent,
  }) async {
    if (primary != null) _settings.primaryColor = primary;
    if (secondary != null) _settings.secondaryColor = secondary;
    if (accent != null) _settings.accentColor = accent;
    _settings.presetId = 'custom';
    await saveTheme();
  }

  ThemePreset? _presetById(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  void _applyPresetToSettings(ThemeSettings target, ThemePreset preset) {
    target.presetId = preset.id;
    target.primaryColor = preset.primary;
    target.secondaryColor = preset.secondary;
    target.accentColor = preset.accent;
    target.backgroundBaseColor = preset.background;
    target.sidebarBaseColor = preset.sidebar;
    target.navIndicatorBaseColor = preset.navIndicator;
    target.textBaseColor = preset.text;
    target.secondaryTextBaseColor = preset.secondaryText;
    target.borderBaseColor = preset.border;
  }

  Future<void> applyPreset(String presetId, {bool save = true}) async {
    final preset = _presetById(presetId);
    if (preset == null) return;
    _applyPresetToSettings(_settings, preset);
    // Update isDark flag based on preset id
    _settings.isDark = presetId.endsWith('_dark');
    if (save) {
      await saveTheme();
    } else {
      notifyListeners();
    }
  }

  Future<void> setBackground(String? path) async =>
      _settings.backgroundImagePath = path;
  Future<void> setBackgroundOpacity(double v) async {
    _settings.backgroundOpacity = v.clamp(0.0, 1.0);
    await saveTheme();
  }

  Future<void> setBlurIntensity(double v) async {
    _settings.blurIntensity = v.clamp(0.0, 20.0);
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
  void dispose() => super.dispose();
}
