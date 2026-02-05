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

  // Статическая функция для затемнения цвета
  static Color darken(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    const size = 140.0;

    final dim = widget.isConnected ? 0.45 : 1.0;
    final topColor = darken(themeManager.settings.primaryColor, dim);
    final bottomColor = darken(themeManager.settings.secondaryColor, dim);
    final glowColor = darken(themeManager.settings.primaryColor, dim * 0.85);

    // Увеличенный glow при наведении
    final hoverGlowOpacity = _isHovered && !widget.isConnecting
        ? (widget.isConnected ? 0.35 : 0.50)
        : (widget.isConnected ? 0.22 : 0.35);

    final hoverGlowRadius = _isHovered && !widget.isConnecting ? 28.0 : 22.0;
    final hoverGlowSpread = _isHovered && !widget.isConnecting ? 6.0 : 4.0;

    return MouseRegion(
      cursor: widget.isConnecting ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isConnecting ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200), // Быстрая анимация hover
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [topColor, bottomColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              // Основной glow
              BoxShadow(
                color: glowColor.withOpacity(hoverGlowOpacity),
                blurRadius: hoverGlowRadius,
                spreadRadius: hoverGlowSpread,
              ),
              // Тень
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Внутренний border
              Container(
                margin: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(_isHovered ? 0.15 : 0.1),
                    width: 1.5,
                  ),
                ),
              ),
              // Блик
              Align(
                alignment: const Alignment(-0.25, -0.55),
                child: Container(
                  width: size * 0.5,
                  height: size * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              // Иконка
              Center(
                child: widget.isConnecting
                    ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                )
                    : Icon(
                  Icons.power_settings_new,
                  color: Colors.white.withOpacity(_isHovered ? 1.0 : 0.95),
                  size: 56,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}