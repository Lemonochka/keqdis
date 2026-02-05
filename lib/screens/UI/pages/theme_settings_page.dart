import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import '../widgets/custom_notification.dart';

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

  @override
  void initState() {
    super.initState();
    _themeManager = ThemeManager();
    _opacity = _themeManager.settings.backgroundOpacity;
    _blur = _themeManager.settings.blurIntensity;
  }

  Future<void> _pickImage() async {
    try {
      // Показываем уведомление о начале обработки
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Обработка изображения...',
          type: NotificationType.info,
        );
      }

      await _themeManager.pickBackgroundImage();

      setState(() {
        _opacity = _themeManager.settings.backgroundOpacity;
        _blur = _themeManager.settings.blurIntensity;
      });
      widget.onThemeChanged?.call();

      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Фон установлен (оптимизировано для производительности)',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _removeBackground() async {
    await _themeManager.removeBackground();
    setState(() {});
    widget.onThemeChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: 'Фон удален',
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
      title: Text('Выберите цвет'),
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
    return Scaffold(
      body: Stack(
        children: [
          // Кастомный фон
          if (_themeManager.hasCustomBackground)
            Positioned.fill(
              child: _buildOptimizedBackground(context),
            ),

          // Контент
          Column(
            children: [
              AppBar(
                backgroundColor: _themeManager.settings.accentColor.withAlpha(230),
                title: const Text('Настройки темы'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // Фоновое изображение
                    Text(
                      'Фоновое изображение',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _themeManager.settings.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Card(
                      color: _themeManager.settings.accentColor.withAlpha(77),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            if (_themeManager.hasCustomBackground) ...[
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text('Фон установлен'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: _removeBackground,
                                    tooltip: 'Удалить фон',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Информация об оптимизации
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
                                        'Изображение оптимизировано до Full HD для лучшей производительности',
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

                              // Opacity slider
                              const Text(
                                'Прозрачность',
                                style: TextStyle(fontSize: 14),
                              ),
                              Slider(
                                value: _opacity,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                label: '${(_opacity * 100).round()}%',
                                onChanged: _updateOpacity,
                              ),
                              const SizedBox(height: 8),

                              // Blur slider
                              const Text(
                                'Размытие',
                                style: TextStyle(fontSize: 14),
                              ),
                              Slider(
                                value: _blur,
                                min: 0.0,
                                max: 20.0,
                                divisions: 20,
                                label: _blur.round().toString(),
                                onChanged: _updateBlur,
                              ),
                            ] else ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _pickImage,
                                  icon: const Icon(Icons.image),
                                  label: const Text('Выбрать изображение'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _themeManager.settings.primaryColor,
                                    padding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Подсказка об автоматическом сжатии
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
                                        'Любое изображение будет автоматически оптимизировано до Full HD (1920x1080) для лучшей производительности',
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

                    // Цвета
                    Text(
                      'Цветовая схема',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _themeManager.settings.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildColorCard(
                      'Основной цвет',
                      _themeManager.settings.primaryColor,
                          () => _pickColor('primary'),
                    ),
                    const SizedBox(height: 12),

                    _buildColorCard(
                      'Вторичный цвет',
                      _themeManager.settings.secondaryColor,
                          () => _pickColor('secondary'),
                    ),
                    const SizedBox(height: 12),

                    _buildColorCard(
                      'Цвет фона карточек',
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

  Widget _buildOptimizedBackground(BuildContext context) {
    final path = _themeManager.settings.backgroundImagePath!;
    final imageProvider = FileImage(File(path));

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio).round();
    final screenHeight = (mediaQuery.size.height * mediaQuery.devicePixelRatio).round();

    final resizedImageProvider = ResizeImage(
      imageProvider,
      width: screenWidth,
      height: screenHeight,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: resizedImageProvider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Ошибка загрузки фонового изображения: $error');
            Future.microtask(() => _themeManager.removeBackground());
            return Container(color: const Color(0xFF0A0E27));
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          child: Container(
            color: Colors.black.withAlpha(((1.0 - _opacity) * 255).round()),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCard(String title, Color color, VoidCallback onTap) {
    return Card(
      color: _themeManager.settings.accentColor.withAlpha(77),
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
}