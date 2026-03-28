import 'package:flutter/material.dart';
import 'package:keqdis/core/tun_service.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

class VpnModeSwitch extends StatelessWidget {
  final VpnMode currentMode;
  final bool tunAvailable;
  final bool isConnected;
  final Function(VpnMode) onModeChanged;

  const VpnModeSwitch({
    super.key,
    required this.currentMode,
    required this.tunAvailable,
    required this.isConnected,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:        s.cardColor,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: s.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label:      'Proxy',
            icon:       Icons.wifi_tethering,
            isSelected: currentMode == VpnMode.systemProxy,
            onTap:      () => onModeChanged(VpnMode.systemProxy),
            isConnected: isConnected,
            settings:   s,
          ),
          const SizedBox(width: 3),
          _ModeButton(
            label:      'TUN',
            icon:       Icons.shield,
            isSelected: currentMode == VpnMode.tun,
            onTap:      () => onModeChanged(VpnMode.tun),
            isConnected: isConnected,
            needsAdmin: !tunAvailable,
            settings:   s,
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool isConnected;
  final bool needsAdmin;
  final ThemeSettings settings;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.isConnected,
    required this.settings,
    this.needsAdmin = false,
  });

  String get _tooltip {
    if (needsAdmin)  return 'TUN режим (требуются права администратора)';
    if (isConnected) return 'Отключитесь для смены режима';
    return label == 'Proxy' ? 'System Proxy' : 'TUN режим';
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final active = isSelected;
    final textColor = needsAdmin
        ? s.secondaryTextColor.withOpacity(0.4)
        : active
        ? (s.isDarkMode ? Colors.white : const Color(0xFF2D2D2D))
        : s.secondaryTextColor;

    return Tooltip(
      message: _tooltip,
      child: GestureDetector(
        onTap: isConnected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve:    Curves.easeOutCubic,
          padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? s.primaryColor.withOpacity(0.85)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size:  16,
                color: active ? Colors.white : textColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color:      active ? Colors.white : textColor,
                ),
              ),
              if (needsAdmin) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock_outline, size: 11, color: s.secondaryTextColor.withOpacity(0.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
