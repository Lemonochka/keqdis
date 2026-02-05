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
    final themeManager = ThemeManager();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: themeManager.settings.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            context,
            label: 'Proxy',
            icon: Icons.wifi_tethering,
            isSelected: currentMode == VpnMode.systemProxy,
            onTap: () => onModeChanged(VpnMode.systemProxy),
          ),
          const SizedBox(width: 4),
          _buildModeButton(
            context,
            label: 'TUN',
            icon: Icons.shield,
            isSelected: currentMode == VpnMode.tun,
            onTap: tunAvailable
                ? () => onModeChanged(VpnMode.tun)
                : null,
            isDisabled: !tunAvailable,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
      BuildContext context, {
        required String label,
        required IconData icon,
        required bool isSelected,
        VoidCallback? onTap,
        bool isDisabled = false,
      }) {
    final themeManager = ThemeManager();

    return Tooltip(
      message: isDisabled
          ? 'TUN режим недоступен'
          : isConnected
          ? 'Отключитесь для смены режима'
          : label == 'Proxy' ? 'System Proxy' : label,
      child: InkWell(
        onTap: isConnected || isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? themeManager.settings.primaryColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
              color: themeManager.settings.primaryColor.withOpacity(0.5),
              width: 1,
            )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDisabled
                    ? Colors.grey
                    : isSelected
                    ? Colors.white
                    : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isDisabled
                      ? Colors.grey
                      : isSelected
                      ? Colors.white
                      : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}