import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'package:keqdis/screens/ping_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/core/tun_service.dart';
import 'package:keqdis/utils/server_name_utils.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

import '../widgets/power_button.dart';
import '../widgets/vpn_mode_switch.dart';
import '../widgets/server_search_bar.dart';
import '../widgets/server_list_item.dart';
import '../widgets/add_server_dialog.dart';
import '../widgets/custom_notification.dart';

import 'subscriptions_screen.dart';
import 'settings_screen.dart';

class HomeMainContent extends StatelessWidget {
  final int currentTab;
  final AppSettings settings;
  final bool tunAvailable;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final Function() onClearSearch;
  final Function() onAddServer;
  final Function(List<ServerItem>) onPingAll;
  final Function(ServerItem) onPing;
  final Map<String, bool> serverPingingState;
  final Function(VpnMode) onVpnModeChanged;
  final VoidCallback onSettingsChanged;

  const HomeMainContent({
    super.key,
    required this.currentTab,
    required this.settings,
    required this.tunAvailable,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onAddServer,
    required this.onPingAll,
    required this.onPing,
    required this.serverPingingState,
    required this.onVpnModeChanged,
    required this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (currentTab) {
      case 0:
        return _buildServerList(context);
      case 1:
        return SubscriptionsView(
          onServersUpdated: () async {
            await Provider.of<VpnController>(context, listen: false).loadInitialServers();
          },
        );
      case 2:
        return SettingsView(
          onSettingsChanged: onSettingsChanged,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServerList(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: ServerSearchBar(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  onClear: onClearSearch,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Tooltip(
                      message: 'Добавить сервер',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: themeManager.settings.accentColor.withAlpha(77),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: themeManager.settings.primaryColor.withAlpha(77),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          onPressed: onAddServer,
                          icon: Icon(
                            Icons.add_rounded,
                            color: themeManager.settings.primaryColor,
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Consumer<PingManager>(
                      builder: (context, pingManager, _) => Tooltip(
                        message: 'Пинг всех серверов',
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: themeManager.settings.accentColor.withAlpha(77),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: themeManager.settings.primaryColor.withAlpha(77),
                              width: 1,
                            ),
                          ),
                          child: IconButton(
                            onPressed: pingManager.isPinging
                                ? null
                                : () => onPingAll(
                                    Provider.of<VpnController>(context, listen: false).searchResults.isNotEmpty
                                        ? Provider.of<VpnController>(context, listen: false).searchResults
                                        : Provider.of<VpnController>(context, listen: false).allServers),
                            icon: pingManager.isPinging
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: themeManager.settings.primaryColor,
                                    ),
                                  )
                                : Icon(
                                    Icons.speed_rounded,
                                    color: themeManager.settings.primaryColor,
                                    size: 22,
                                  ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer2<VpnController, PingManager>(
                  builder: (context, controller, pingManager, _) {
                    final servers = searchController.text.isNotEmpty
                        ? controller.searchResults
                        : controller.allServers;

                    if (servers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              searchController.text.isEmpty ? Icons.dns_outlined : Icons.search_off,
                              size: 64,
                              color: Colors.white.withAlpha(77),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              searchController.text.isEmpty
                                  ? 'Нет серверов'
                                  : 'Серверы не найдены',
                              style: TextStyle(
                                color: Colors.white.withAlpha(128),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16),
                      itemCount: servers.length,
                      cacheExtent: 500,
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        final isSelected = server.id == controller.selectedServer?.id;
                        final isConnected = isSelected && controller.isConnected;
                        final pingResult = pingManager.getPingResult(server);
                        final isPinging = serverPingingState[server.id] ?? false;

                        return ServerListItem(
                          key: ValueKey(server.id),
                          server: server,
                          isSelected: isSelected,
                          isConnected: isConnected,
                          pingResult: pingResult,
                          isPinging: isPinging,
                          isAnyServerConnected: controller.isConnected,
                          onTap: () => controller.selectServer(server),
                          onFavoriteToggle: () => controller.toggleFavorite(server.id),
                          onPing: () => onPing(server),
                          onDelete: () async {
                            await controller.deleteServer(server.id);
                            CustomNotification.show(
                              context,
                              message: 'Сервер удален',
                              type: NotificationType.success,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: themeManager.settings.accentColor.withAlpha(77),
            border: Border(
              left: BorderSide(
                color: Colors.white.withAlpha(13),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              const Spacer(),
              Consumer<VpnController>(
                builder: (context, controller, _) => PowerButton(
                  isConnected: controller.isConnected,
                  isConnecting: controller.isConnecting,
                  onTap: controller.toggleConnection,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer<VpnController>(
                  builder: (context, controller, _) {
                    if (controller.selectedServer == null) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: themeManager.settings.accentColor.withAlpha(51),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withAlpha(26),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 28,
                              color: Colors.white.withAlpha(128),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Выберите сервер',
                              style: TextStyle(
                                color: Colors.white.withAlpha(128),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final server = controller.selectedServer!;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: themeManager.settings.accentColor.withAlpha(51),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withAlpha(26),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Выбранный сервер',
                            style: TextStyle(
                              color: Colors.white.withAlpha(179),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ServerNameUtils.formatForDisplay(
                              server.displayName,
                              maxLength: 25,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Consumer<VpnController>(
                  builder: (context, controller, _) => VpnModeSwitch(
                    currentMode: controller.vpnMode,
                    tunAvailable: tunAvailable,
                    isConnected: controller.isConnected,
                    onModeChanged: onVpnModeChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
