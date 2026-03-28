import 'dart:math';
import 'dart:ui';
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
        return SettingsView(onSettingsChanged: onSettingsChanged);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServerList(BuildContext context) {
    final themeManager = Provider.of<ThemeManager>(context);
    final s = themeManager.settings;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Левая панель: поиск + список серверов ──────────────────────────
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Строка поиска
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: ServerSearchBar(
                  controller: searchController,
                  onChanged:  onSearchChanged,
                  onClear:    onClearSearch,
                ),
              ),

              // Кнопки действий
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    // Кнопка "Добавить сервер"
                    Tooltip(
                      message: 'Добавить сервер',
                      child: _ActionButton(
                        icon: Icons.add_rounded,
                        onTap: onAddServer,
                        settings: s,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Кнопка "Пинг всех"
                    Consumer<PingManager>(
                      builder: (_, pingManager, __) => Tooltip(
                        message: 'Пинг всех серверов',
                        child: _ActionButton(
                          icon:  Icons.speed_rounded,
                          onTap: pingManager.isPinging
                              ? null
                              : () => onPingAll(
                            Provider.of<VpnController>(context, listen: false)
                                .searchResults
                                .isNotEmpty
                                ? Provider.of<VpnController>(context, listen: false)
                                .searchResults
                                : Provider.of<VpnController>(context, listen: false)
                                .allServers,
                          ),
                          settings: s,
                          isLoading: pingManager.isPinging,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Волновая анимация — разделитель
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: WaveAnimation(),
              ),

              // Список серверов
              Expanded(
                child: Consumer2<VpnController, PingManager>(
                  builder: (context, controller, pingManager, _) {
                    final servers = searchController.text.isNotEmpty
                        ? controller.searchResults
                        : controller.allServers;

                    if (servers.isEmpty) {
                      return _EmptyState(
                        icon: searchController.text.isEmpty
                            ? Icons.dns_outlined
                            : Icons.search_off,
                        text: searchController.text.isEmpty
                            ? 'Нет серверов'
                            : 'Серверы не найдены',
                        settings: s,
                      );
                    }

                    return _GroupedServerList(
                      servers:             servers,
                      controller:          controller,
                      pingManager:         pingManager,
                      searchController:    searchController,
                      serverPingingState:  serverPingingState,
                      onPing:              onPing,
                      context:             context,
                      settings:            s,
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // ── Вертикальный разделитель ───────────────────────────────────────
        Container(width: 1, color: s.borderColor),

        // ── Правая панель: кнопка питания + режим VPN ─────────────────────
        // Glassmorphism когда есть фоновое изображение
        ClipRect(
          child: BackdropFilter(
            filter: themeManager.hasCustomBackground
                ? ImageFilter.blur(sigmaX: 14, sigmaY: 14)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              width: 260,
              color: themeManager.hasCustomBackground
                  ? Colors.black.withOpacity(0.22)
                  : (s.isDarkMode ? s.sidebarColor : s.sidebarColor.withOpacity(0.85)),
              child: Column(
                children: [
                  const Spacer(),

                  // Кнопка питания
                  Consumer<VpnController>(
                    builder: (_, controller, __) => PowerButton(
                      isConnected:  controller.isConnected,
                      isConnecting: controller.isConnecting,
                      onTap:        controller.toggleConnection,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Информация о подключении
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Consumer<VpnController>(
                      builder: (_, controller, __) {
                        if (controller.selectedServer == null) {
                          return _ServerInfoCard(
                            title: 'Выберите сервер',
                            body:  '',
                            settings: s,
                            isEmpty: true,
                          );
                        }
                        return _ServerInfoCard(
                          title: 'Выбранный сервер',
                          body: ServerNameUtils.formatForDisplay(
                            controller.selectedServer!.displayName,
                            maxLength: 28,
                          ),
                          settings: s,
                        );
                      },
                    ),
                  ),

                  const Spacer(),

                  // VPN Mode Switch
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Consumer<VpnController>(
                      builder: (_, controller, __) => VpnModeSwitch(
                        currentMode:   controller.vpnMode,
                        tunAvailable:  tunAvailable,
                        isConnected:   controller.isConnected,
                        onModeChanged: onVpnModeChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),   // Container (правая панель)
          ),   // BackdropFilter
        ),   // ClipRect
      ],
    );
  }
}

// ─── Сгруппированный список серверов ──────────────────────────────────────────
class _GroupedServerList extends StatelessWidget {
  final List<ServerItem> servers;
  final VpnController controller;
  final PingManager pingManager;
  final TextEditingController searchController;
  final Map<String, bool> serverPingingState;
  final Function(ServerItem) onPing;
  final BuildContext context;
  final ThemeSettings settings;

  const _GroupedServerList({
    required this.servers,
    required this.controller,
    required this.pingManager,
    required this.searchController,
    required this.serverPingingState,
    required this.onPing,
    required this.context,
    required this.settings,
  });

  @override
  Widget build(BuildContext _) {
    // Собираем плоский список виджетов с заголовками групп
    final List<Widget> items = [];
    String? lastSubId;

    for (final server in servers) {
      final subId = server.subscriptionId;
      if (subId != lastSubId) {
        lastSubId = subId;
        items.add(_SubscriptionHeader(
          label:    server.subscriptionName ?? 'Ручные серверы',
          settings: settings,
        ));
      }
      final isSelected  = server.id == controller.selectedServer?.id;
      final isConnected = isSelected && controller.isConnected;
      items.add(ServerListItem(
        key:                ValueKey(server.id),
        server:             server,
        isSelected:         isSelected,
        isConnected:        isConnected,
        pingResult:         pingManager.getPingResult(server),
        isPinging:          serverPingingState[server.id] ?? false,
        isAnyServerConnected: controller.isConnected,
        onTap:              () => controller.selectServer(server),
        onFavoriteToggle:   () => controller.toggleFavorite(server.id),
        onPing:             () => onPing(server),
        onDelete:           () async {
          await controller.deleteServer(server.id);
          CustomNotification.show(context, message: 'Сервер удалён', type: NotificationType.success);
        },
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 20),
      children: items,
    );
  }
}

// ─── Заголовок группы подписки ────────────────────────────────────────────────
class _SubscriptionHeader extends StatelessWidget {
  final String label;
  final ThemeSettings settings;

  const _SubscriptionHeader({required this.label, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize:      11,
                fontWeight:    FontWeight.w600,
                color:         settings.secondaryTextColor.withOpacity(0.7),
                letterSpacing: 0.8,
              ),
            ),
          ),
          Icon(Icons.refresh,       size: 16, color: settings.secondaryTextColor.withOpacity(0.45)),
          const SizedBox(width: 8),
          Icon(Icons.download_rounded, size: 16, color: settings.secondaryTextColor.withOpacity(0.45)),
        ],
      ),
    );
  }
}

// ─── Кнопка действия (добавить / пинг) ───────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final ThemeSettings settings;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.settings,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width:  38,
        height: 38,
        decoration: BoxDecoration(
          color:        settings.primaryColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: settings.primaryColor.withOpacity(0.3)),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: settings.primaryColor,
            ),
          )
              : Icon(icon, color: settings.primaryColor, size: 20),
        ),
      ),
    );
  }
}

// ─── Карточка с инфо о сервере ────────────────────────────────────────────────
class _ServerInfoCard extends StatelessWidget {
  final String title;
  final String body;
  final ThemeSettings settings;
  final bool isEmpty;

  const _ServerInfoCard({
    required this.title,
    required this.body,
    required this.settings,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        settings.cardColor,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: settings.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEmpty)
            Icon(Icons.info_outline, size: 26, color: settings.secondaryTextColor),
          if (isEmpty) const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color:    settings.secondaryTextColor,
              fontSize: 11,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                color:      settings.textColor,
                fontSize:   13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Пустой экран ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeSettings settings;

  const _EmptyState({required this.icon, required this.text, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: settings.secondaryTextColor.withOpacity(0.35)),
          const SizedBox(height: 16),
          Text(text,
              style: TextStyle(color: settings.secondaryTextColor, fontSize: 15)),
        ],
      ),
    );
  }
}

// ─── Волновая анимация ────────────────────────────────────────────────────────
class WaveAnimation extends StatefulWidget {
  const WaveAnimation({super.key});

  @override
  State<WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<WaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder:   (_, __) => CustomPaint(
          painter: _WavePainter(offset: _ctrl.value),
          size:    Size.infinite,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double offset;
  _WavePainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = ThemeSettings.waveColor
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap   = StrokeCap.round;

    final path = Path();
    const amplitude = 7.0;
    const waveLength = 60.0; // px между пиками

    path.moveTo(0, size.height / 2);
    for (double x = 0; x <= size.width; x++) {
      final y = amplitude *
          sin(2 * pi * (x / waveLength - offset)) +
          size.height / 2;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.offset != offset;
}
