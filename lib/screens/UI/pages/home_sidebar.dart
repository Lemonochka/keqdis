import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import '../widgets/connection_status.dart';

class HomeSidebar extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;

  const HomeSidebar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: themeManager.settings.accentColor.withAlpha(77),
        border: Border(
          right: BorderSide(
            color: Colors.white.withAlpha(13),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Consumer<VpnController>(
              builder: (context, controller, _) => ConnectionStatus(
                status: controller.isConnected
                    ? 'Подключено'
                    : controller.isConnecting
                        ? 'Подключение...'
                        : 'Отключено',
                isConnected: controller.isConnected,
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavButton(
                  themeManager: themeManager,
                  icon: Icons.dns,
                  label: 'Серверы',
                  isSelected: currentTab == 0,
                  onTap: () => onTabChanged(0),
                ),
                _buildNavButton(
                  themeManager: themeManager,
                  icon: Icons.rss_feed,
                  label: 'Подписки',
                  isSelected: currentTab == 1,
                  onTap: () => onTabChanged(1),
                ),
                _buildNavButton(
                  themeManager: themeManager,
                  icon: Icons.settings,
                  label: 'Настройки',
                  isSelected: currentTab == 2,
                  onTap: () => onTabChanged(2),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'v1.2.1',
              style: TextStyle(
                color: Colors.white.withAlpha(77),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required ThemeManager themeManager,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? themeManager.settings.primaryColor.withAlpha(51)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: themeManager.settings.primaryColor.withAlpha(128),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? themeManager.settings.primaryColor
                      : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

