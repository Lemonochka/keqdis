import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import '../widgets/custom_notification.dart';
import 'package:keqdis/localization/app_localization.dart';

class ThemeSettingsPage extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  const ThemeSettingsPage({super.key, this.onThemeChanged});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late ThemeManager _themeManager;
  double _opacity = 0.3;
  double _blur = 10.0;
  bool _showDarkThemes = false;

  ImageProvider? _cachedBackgroundImage;
  String? _currentBackgroundPath;

    @override
  void initState() {
    super.initState();
    _themeManager = ThemeManager();
    _opacity = _themeManager.settings.backgroundOpacity;
    _blur = _themeManager.settings.blurIntensity;
    _showDarkThemes = _themeManager.settings.isDark;
    _updateCachedImage();
  }

  void _updateCachedImage() {
    final path = _themeManager.settings.backgroundImagePath;
    if (path != _currentBackgroundPath) {
      _currentBackgroundPath = path;
      if (path != null) {
        _cachedBackgroundImage = FileImage(File(path));
      } else {
        _cachedBackgroundImage = null;
      }
    }
  }

  @override
  void didUpdateWidget(covariant ThemeSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCachedImage();
  }

  Future<void> _pickImage() async {
    try {
      if (mounted) {
        CustomNotification.show(
          context,
          message: AppLocalization().t('processing_image'),
          type: NotificationType.info,
        );
      }

      await _themeManager.pickBackgroundImage();

      setState(() {
        _opacity = _themeManager.settings.backgroundOpacity;
        _blur = _themeManager.settings.blurIntensity;
        _updateCachedImage();
      });
      widget.onThemeChanged?.call();

      if (mounted) {
        CustomNotification.show(
          context,
          message: AppLocalization().t('background_set_optimized'),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: AppLocalization().t('background_error').replaceFirst('{error}', '$e'),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _removeBackground() async {
    await _themeManager.removeBackground();
    setState(() {
      _updateCachedImage();
    });
    widget.onThemeChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: AppLocalization().t('background_removed'),
        type: NotificationType.success,
      );
    }
  }

  Future<void> _updateOpacity(double value) async {
    setState(() => _opacity = value);
    _themeManager.updateOpacity(value);
    await _themeManager.saveTheme();
    widget.onThemeChanged?.call();
  }

  Future<void> _updateBlur(double value) async {
    setState(() => _blur = value);
    _themeManager.updateBlur(value);
    await _themeManager.saveTheme();
    widget.onThemeChanged?.call();
  }

  Future<void> _pickColor(String type) async {
    Color currentColor;

    switch (type) {
      case 'primary':
        currentColor = _themeManager.settings.primaryColor;
        break;
      case 'secondary':
        currentColor = _themeManager.settings.secondaryColor;
        break;
      case 'accent':
        currentColor = _themeManager.settings.accentColor;
        break;
      default:
        return;
    }

    final pickedColor = await showColorPickerDialog(
      context,
      currentColor,
      title: Text(AppLocalization().t('pick_color_title')),
      pickersEnabled: const {
        ColorPickerType.wheel: true,
        ColorPickerType.accent: false,
      },
    );

    if (pickedColor != currentColor) {
      switch (type) {
        case 'primary':
          await _themeManager.setPrimaryColor(pickedColor);
          break;
        case 'secondary':
          await _themeManager.setCustomColors(secondary: pickedColor);
          break;
        case 'accent':
          await _themeManager.setAccentColor(pickedColor);
          break;
      }

      setState(() {});
      widget.onThemeChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 700,
          maxHeight: 800,
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final s = _themeManager.settings;
    return Scaffold(
      body: Stack(
        children: [
          if (_themeManager.hasCustomBackground && _cachedBackgroundImage != null)
            Positioned.fill(
              child: _buildOptimizedBackground(),
            ),

          Column(
            children: [
              AppBar(
                              backgroundColor: _themeManager.hasCustomBackground
                                  ? (s.isDark ? const Color(0xFF141010) : const Color(0xFFF5E6EA))
                                  : null,
                surfaceTintColor: Colors.transparent,
                foregroundColor: s.textColor,
                title: Text(AppLocalization().t('theme_settings_title')),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      AppLocalization().t('background_image_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_themeManager.hasCustomBackground) ...[
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(AppLocalization().t('background_set')),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: _removeBackground,
                                    tooltip: AppLocalization().t('background_delete'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.blue[300],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        AppLocalization().t('background_optimized_hint'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue[200],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Divider(height: 24),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalization().t('background_transparency'),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    '${(_opacity * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _themeManager.settings.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: _themeManager.settings.primaryColor,
                                  inactiveTrackColor: _themeManager.settings.primaryColor.withOpacity(0.3),
                                  thumbColor: _themeManager.settings.primaryColor,
                                  overlayColor: _themeManager.settings.primaryColor.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: _opacity.clamp(0.0, 1.0),
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 100,
                                  label: '${(_opacity * 100).round()}%',
                                  onChanged: _updateOpacity,
                                ),
                              ),
                              const SizedBox(height: 8),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalization().t('background_blur_label'),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  Text(
                                    _blur.round().toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _themeManager.settings.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: _themeManager.settings.primaryColor,
                                  inactiveTrackColor: _themeManager.settings.primaryColor.withOpacity(0.3),
                                  thumbColor: _themeManager.settings.primaryColor,
                                  overlayColor: _themeManager.settings.primaryColor.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: _blur.clamp(0.0, 20.0),
                                  min: 0.0,
                                  max: 20.0,
                                  divisions: 40,
                                  label: _blur.round().toString(),
                                  onChanged: _updateBlur,
                                ),
                              ),
                            ] else ...[
                              SizedBox(
                                width: double.infinity,
                                  child: ElevatedButton.icon(
                                  onPressed: _pickImage,
                                  icon: const Icon(Icons.image),
                                  label: Text(AppLocalization().t('background_pick_image')),
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                                ),
                              ),
                              const SizedBox(height: 12),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lightbulb_outline,
                                      color: Colors.orange[300],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        AppLocalization().t('background_any_image_hint'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange[200],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Выбор темы
                    _buildThemeSection(),

                    const SizedBox(height: 32),

                    // Цвета
                    Text(
                      AppLocalization().t('color_scheme'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildColorCard(
                      AppLocalization().t('primary_color'),
                      _themeManager.settings.primaryColor,
                          () => _pickColor('primary'),
                    ),
                    const SizedBox(height: 12),

                    _buildColorCard(
                      AppLocalization().t('secondary_color'),
                      _themeManager.settings.secondaryColor,
                          () => _pickColor('secondary'),
                    ),
                    const SizedBox(height: 12),

                    _buildColorCard(
                      AppLocalization().t('card_background_color'),
                      _themeManager.settings.accentColor,
                          () => _pickColor('accent'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _cachedBackgroundImage!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Ошибка загрузки фонового изображения: $error');
            Future.microtask(() => _themeManager.removeBackground());
            return Container(color: const Color(0xFF0A0E27));
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _blur.clamp(0.0, 20.0),
            sigmaY: _blur.clamp(0.0, 20.0),
          ),
          child: Container(
            color: Colors.black.withAlpha(
              ((1.0 - _opacity.clamp(0.0, 1.0)) * 255).round().clamp(0, 255),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCard(String title, Color color, VoidCallback onTap) {
      return Card(
        child: ListTile(
          title: Text(title),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24, width: 2),
            ),
          ),
          trailing: const Icon(Icons.edit),
          onTap: onTap,
        ),
      );
    }

    Widget _buildThemeSection() {
      final presets = _themeManager.presets;
      final lightPresets = presets.where((p) => !p.id.endsWith('_dark')).toList();
      final darkPresets = presets.where((p) => p.id.endsWith('_dark')).toList();
      final currentIsDark = _themeManager.settings.isDark;
    
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                currentIsDark ? 'Dark Themes' : 'Light Themes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: currentIsDark
                      ? Colors.indigo.withOpacity(0.2)
                      : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: currentIsDark
                        ? Colors.indigo.withOpacity(0.4)
                        : Colors.amber.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildThemeModeButton(
                      icon: Icons.light_mode,
                      label: 'Light',
                      isSelected: !currentIsDark,
                      onTap: () async {
                        await _themeManager.setDarkMode(false);
                        setState(() => _showDarkThemes = false);
                        widget.onThemeChanged?.call();
                      },
                    ),
                    _buildThemeModeButton(
                      icon: Icons.dark_mode,
                      label: 'Dark',
                      isSelected: currentIsDark,
                      onTap: () async {
                        await _themeManager.setDarkMode(true);
                        setState(() => _showDarkThemes = true);
                        widget.onThemeChanged?.call();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: (_showDarkThemes ? darkPresets : lightPresets).map((preset) {
              final isSelected = _themeManager.settings.presetId == preset.id;
              return _buildThemePresetCard(preset, isSelected);
            }).toList(),
          ),
        ],
      );
    }

    Widget _buildThemeModeButton({
      required IconData icon,
      required String label,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? _themeManager.settings.primaryColor
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : _themeManager.settings.secondaryTextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : _themeManager.settings.textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildThemePresetCard(ThemePreset preset, bool isSelected) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await _themeManager.applyPreset(preset.id);
            setState(() {
              _showDarkThemes = preset.id.endsWith('_dark');
            });
            widget.onThemeChanged?.call();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: preset.accent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? _themeManager.settings.primaryColor
                    : preset.border,
                width: isSelected ? 2.5 : 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _themeManager.settings.primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        preset.primary,
                        preset.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: preset.background.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: preset.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: preset.text,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isSelected) ...[
                  const SizedBox(height: 2),
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: preset.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
  }