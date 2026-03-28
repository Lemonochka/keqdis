import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';

class HomeTopBar extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;

  const HomeTopBar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager  = Provider.of<ThemeManager>(context);
    final s             = themeManager.settings;
    final hasBackground = themeManager.hasCustomBackground;

    return ClipRect(
      child: BackdropFilter(
        // Размытие подложки под баром когда есть фон
        filter: hasBackground
            ? ImageFilter.blur(sigmaX: 18, sigmaY: 18)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          decoration: BoxDecoration(
            color: hasBackground
                ? Colors.black.withOpacity(0.28)
                : s.sidebarColor,
            border: Border(
              bottom: BorderSide(color: s.borderColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width:  1,
                height: 22,
                color:  s.borderColor,
                margin: const EdgeInsets.only(right: 8),
              ),

              _TabIconButton(
                icon:       Icons.dns_rounded,
                tooltip:    'Серверы',
                tab:        0,
                currentTab: currentTab,
                settings:   s,
                onTap:      () => onTabChanged(0),
              ),
              _TabIconButton(
                icon:       Icons.language_rounded,
                tooltip:    'Подписки',
                tab:        1,
                currentTab: currentTab,
                settings:   s,
                onTap:      () => onTabChanged(1),
              ),
              _TabIconButton(
                icon:       Icons.settings_rounded,
                tooltip:    'Настройки',
                tab:        2,
                currentTab: currentTab,
                settings:   s,
                onTap:      () => onTabChanged(2),
              ),

              const Spacer(),

              Consumer<VpnController>(
                builder: (_, ctrl, __) => Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: _ConnectionDot(
                    isConnected:  ctrl.isConnected,
                    isConnecting: ctrl.isConnecting,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final int tab;
  final int currentTab;
  final ThemeSettings settings;
  final VoidCallback onTap;

  const _TabIconButton({
    required this.icon,
    required this.tooltip,
    required this.tab,
    required this.currentTab,
    required this.settings,
    required this.onTap,
  });

  @override
  State<_TabIconButton> createState() => _TabIconButtonState();
}

class _TabIconButtonState extends State<_TabIconButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  bool get isActive => widget.tab == widget.currentTab;

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;

    return Tooltip(
      message:    widget.tooltip,
      preferBelow: true,
      decoration: BoxDecoration(
        color:        s.cardColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: s.borderColor),
      ),
      textStyle: TextStyle(color: s.textColor, fontSize: 12),
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          _scaleCtrl.forward();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          _scaleCtrl.reverse();
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: _scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve:    Curves.easeOutCubic,
              margin:   const EdgeInsets.symmetric(horizontal: 3),
              padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                // M3 Expressive: pill indicator when active
                color: isActive
                    ? s.primaryColor.withOpacity(0.2)
                    : _hovered
                    ? s.primaryColor.withOpacity(0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                widget.icon,
                size:  22,
                color: isActive
                    ? s.primaryColor
                    : _hovered
                    ? s.primaryColor.withOpacity(0.8)
                    : ThemeSettings.inactiveNavColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionDot extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;

  const _ConnectionDot({
    required this.isConnected,
    required this.isConnecting,
  });

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = Tween<double>(begin: 0.85, end: 1.2).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_ConnectionDot old) {
    super.didUpdateWidget(old);
    if (widget.isConnecting && !old.isConnecting) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isConnecting) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    if (widget.isConnected) {
      dotColor = const Color(0xFF4CAF50); // зелёный
    } else if (widget.isConnecting) {
      dotColor = const Color(0xFFFFA726); // оранжевый
    } else {
      dotColor = const Color(0xFF757575); // серый
    }

    return Tooltip(
      message: widget.isConnected
          ? 'Подключено'
          : widget.isConnecting
          ? 'Подключение...'
          : 'Отключено',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Transform.scale(
          scale: widget.isConnecting ? _pulse.value : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width:  12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: widget.isConnected || widget.isConnecting
                  ? [
                BoxShadow(
                  color:       dotColor.withOpacity(0.55),
                  blurRadius:  8,
                  spreadRadius: 2,
                ),
              ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
