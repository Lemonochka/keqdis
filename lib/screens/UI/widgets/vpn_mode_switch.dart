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
            // Кнопка всегда кликабельна.
            // Если нет прав админа — home_screen перехватит вызов и покажет UAC-диалог.
            onTap: () => onModeChanged(VpnMode.tun),
            // Показываем визуальную подсказку что нужны права, но не блокируем клик
            needsAdmin: !tunAvailable,
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
        bool needsAdmin = false,
      }) {
    final themeManager = ThemeManager();

    String tooltip;
    if (needsAdmin) {
      tooltip = 'TUN режим (требуются права администратора)';
    } else if (isConnected) {
      tooltip = 'Отключитесь для смены режима';
    } else {
      tooltip = label == 'Proxy' ? 'System Proxy' : label;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        // Блокируем только если уже подключены (смена режима на лету через диалог)
        onTap: isConnected ? null : onTap,
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
                // Если нужны права — иконка с замочком-оттенком, но не серая
                color: needsAdmin
                    ? Colors.white54
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
                  color: needsAdmin
                      ? Colors.white54
                      : isSelected
                      ? Colors.white
                      : Colors.white70,
                ),
              ),
              // Маленький значок щита если нужны права
              if (needsAdmin) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.lock_outline,
                  size: 11,
                  color: Colors.white38,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}