import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

class PowerButton extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback? onTap;

  const PowerButton({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    this.onTap,
  });

  @override
  State<PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<PowerButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    const size = 140.0;

    // Кнопка теперь следует активному цветовому пресету.
    final btnColor = widget.isConnected
        ? themeManager.settings.powerButtonColor.withOpacity(0.7)
        : themeManager.settings.powerButtonColor;

    final glowColor = themeManager.settings.powerButtonGlow;
    final glowOpacity = _isHovered && !widget.isConnecting ? 0.52 : 0.36;
    final glowRadius = _isHovered && !widget.isConnecting ? 32.0 : 22.0;
    final glowSpread = _isHovered && !widget.isConnecting ? 8.0 : 4.0;

    // Иконка: пауза когда подключено, питание когда нет
    final iconData = widget.isConnected
        ? Icons.pause
        : Icons.power_settings_new;
    final iconShouldBeLight =
        ThemeData.estimateBrightnessForColor(btnColor) == Brightness.dark;
    final iconColor = iconShouldBeLight
        ? Colors.white.withOpacity(_isHovered ? 1.0 : 0.9)
        : Colors.black.withOpacity(_isHovered ? 0.75 : 0.6);

    return MouseRegion(
      cursor: widget.isConnecting
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isConnecting ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: btnColor,
            boxShadow: [
              // Розовый glow (усиливается при hover и в dark-теме)
              BoxShadow(
                color: glowColor.withOpacity(glowOpacity),
                blurRadius: glowRadius,
                spreadRadius: glowSpread,
              ),
              // Мягкая тень
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isConnecting
                ? CircularProgressIndicator(
                    color: themeManager.settings.primaryColor,
                    strokeWidth: 3,
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      iconData,
                      key: ValueKey(iconData),
                      color: iconColor,
                      size: 52,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
