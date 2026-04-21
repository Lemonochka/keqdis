import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'package:keqdis/screens/ping_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/core/tun_service.dart';
import 'package:keqdis/services/improved_subscription_service.dart';
import 'package:keqdis/utils/server_name_utils.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/localization/app_localization.dart';

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
  final bool enableWaveAnimation;
  final bool isDesktopLayout;

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
    required this.enableWaveAnimation,
    this.isDesktopLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (currentTab) {
      case 0:
        return _buildServerList(context);
      case 1:
        return SubscriptionsView(
          onServersUpdated: () async {
            await Provider.of<VpnController>(
              context,
              listen: false,
            ).loadInitialServers();
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
    final scheme = Theme.of(context).colorScheme;

    final rightPanelWidth = isDesktopLayout ? 300.0 : 260.0;

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
                  onChanged: onSearchChanged,
                  onClear: onClearSearch,
                ),
              ),

              // Кнопки действий
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    // Кнопка "Добавить сервер"
                    Tooltip(
                      message: context.tr('add_server'),
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
                        message: context.tr('ping_all_servers'),
                        child: _ActionButton(
                          icon: Icons.speed_rounded,
                          onTap: pingManager.isPinging
                              ? null
                              : () => onPingAll(
                                  Provider.of<VpnController>(
                                        context,
                                        listen: false,
                                      ).searchResults.isNotEmpty
                                      ? Provider.of<VpnController>(
                                          context,
                                          listen: false,
                                        ).searchResults
                                      : Provider.of<VpnController>(
                                          context,
                                          listen: false,
                                        ).allServers,
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Consumer<VpnController>(
                  builder: (_, ctrl, __) => WaveAnimation(
                    isActive: enableWaveAnimation && currentTab == 0,
                    isConnected: ctrl.isConnected,
                  ),
                ),
              ),

              // Список серверов
              Expanded(
                child: Stack(
                  children: [
                    Consumer2<VpnController, PingManager>(
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
                                ? context.tr('no_servers')
                                : context.tr('servers_not_found'),
                            settings: s,
                          );
                        }

                        return _GroupedServerList(
                          servers: servers,
                          controller: controller,
                          pingManager: pingManager,
                          searchController: searchController,
                          serverPingingState: serverPingingState,
                          onPing: onPing,
                          context: context,
                          settings: s,
                        );
                      },
                    ),
                    // "Fog" overlay to soften transition from the wave to cards.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                s.backgroundColor,
                                s.backgroundColor.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Вертикальный разделитель ───────────────────────────────────────
        VerticalDivider(width: 1, thickness: 1, color: s.borderColor),

        // ── Правая панель: кнопка питания + режим VPN ─────────────────────
        // Glassmorphism когда есть фоновое изображение
        ClipRect(
          child: BackdropFilter(
            filter: themeManager.hasCustomBackground
                ? ImageFilter.blur(sigmaX: 14, sigmaY: 14)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Container(
              width: rightPanelWidth,
              color: themeManager.hasCustomBackground
                  ? Colors.black.withOpacity(0.22)
                  : scheme.surface,
              child: Column(
                children: [
                  const Spacer(),

                  // Кнопка питания
                  Consumer<VpnController>(
                    builder: (_, controller, __) => PowerButton(
                      isConnected: controller.isConnected,
                      isConnecting: controller.isConnecting,
                      onTap: controller.toggleConnection,
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
                            title: context.tr('select_server'),
                            body: '',
                            settings: s,
                            isEmpty: true,
                          );
                        }
                        return _ServerInfoCard(
                          title: context.tr('selected_server'),
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
                        currentMode: controller.vpnMode,
                        tunAvailable: tunAvailable,
                        isConnected: controller.isConnected,
                        onModeChanged: onVpnModeChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ), // Container (правая панель)
          ), // BackdropFilter
        ), // ClipRect
      ],
    );
  }
}

// ─── Сгруппированный список серверов ──────────────────────────────────────────
class _GroupedServerList extends StatefulWidget {
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
  State<_GroupedServerList> createState() => _GroupedServerListState();
}

class _GroupedServerListState extends State<_GroupedServerList> {
  final Set<String> _refreshingSubscriptions = <String>{};
  final Set<String> _downloadingSubscriptions = <String>{};
  Map<String, Subscription> _subscriptionsById = const {};
  Map<String, int> _subscriptionOrder = const {};
  Map<String, bool> _collapsedGroups = const {};

  @override
  void initState() {
    super.initState();
    _reloadSubscriptionMeta();
    _loadCollapsedGroups();
  }

  @override
  void didUpdateWidget(covariant _GroupedServerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.servers, widget.servers)) {
      _reloadSubscriptionMeta();
    }
  }

  Future<void> _reloadSubscriptionMeta() async {
    final subs = await SubscriptionService.loadSubscriptions();
    if (!mounted) return;
    setState(() {
      _subscriptionsById = {for (final sub in subs) sub.id: sub};
      _subscriptionOrder = {
        for (int i = 0; i < subs.length; i++) subs[i].id: i,
      };
    });
  }

  Future<void> _loadCollapsedGroups() async {
    final state = await SettingsStorage.loadCollapsedServerGroups();
    if (!mounted) return;
    setState(() {
      _collapsedGroups = state;
    });
  }

  Future<void> _toggleGroupCollapse(String key) async {
    final next = <String, bool>{..._collapsedGroups};
    next[key] = !(next[key] ?? false);
    setState(() => _collapsedGroups = next);
    await SettingsStorage.saveCollapsedServerGroups(next);
  }

  String? _trafficLabelForSubscription(String? subscriptionId) {
    if (subscriptionId == null) return null;
    final sub = _subscriptionsById[subscriptionId];
    if (sub == null) {
      return null;
    }
    final used =
        (sub.trafficUploadBytes ?? 0) + (sub.trafficDownloadBytes ?? 0);
    final total = (sub.trafficTotalBytes == null || sub.trafficTotalBytes! <= 0)
        ? '∞'
        : _formatBytes(sub.trafficTotalBytes!);
    return '${_formatBytes(used)} / $total';
  }

  String? _expiryLabelForSubscription(String? subscriptionId) {
    if (subscriptionId == null) return null;
    final exp = _subscriptionsById[subscriptionId]?.expiresAt;
    if (exp == null) return null;
    final now = DateTime.now();
    if (exp.isBefore(now)) return AppLocalization().t('expiry_passed');
    final d = exp.difference(now);
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) {
      return AppLocalization()
          .t('expiry_left_days_hours')
          .replaceFirst('{days}', '$days')
          .replaceFirst('{hours}', '$hours');
    }
    return AppLocalization()
        .t('expiry_left_hours_minutes')
        .replaceFirst('{hours}', '${d.inHours}')
        .replaceFirst('{minutes}', '$mins');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx++;
    }
    final frac = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(frac)} ${units[idx]}';
  }

  Future<void> _refreshSubscription(String subscriptionId) async {
    if (_refreshingSubscriptions.contains(subscriptionId)) return;
    setState(() => _refreshingSubscriptions.add(subscriptionId));
    try {
      final subscriptions = await SubscriptionService.loadSubscriptions();
      final sub = subscriptions
          .where((e) => e.id == subscriptionId)
          .firstOrNull;
      if (!mounted) return;
      if (sub == null) {
        CustomNotification.show(
          context,
          message: 'Подписка не найдена',
          type: NotificationType.error,
        );
        return;
      }

      final result = await SubscriptionService.updateSubscriptionServers(sub);
      if (!mounted) return;
      if (result.success) {
        await widget.controller.loadInitialServers();
        await _reloadSubscriptionMeta();
        if (!mounted) return;
        CustomNotification.show(
          context,
          message:
              'Подписка "${sub.name}" обновлена: ${result.serverCount} серверов',
          type: NotificationType.success,
        );
      } else {
        CustomNotification.show(
          context,
          message: result.error ?? 'Не удалось обновить подписку',
          type: NotificationType.error,
        );
      }
    } catch (e) {
      CustomNotification.show(
        context,
        message: 'Ошибка обновления: $e',
        type: NotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingSubscriptions.remove(subscriptionId));
      }
    }
  }

  Future<void> _downloadSubscriptionConfigs(String subscriptionId) async {
    if (_downloadingSubscriptions.contains(subscriptionId)) return;
    setState(() => _downloadingSubscriptions.add(subscriptionId));
    try {
      final subServers = widget.controller.allServers
          .where((s) => s.subscriptionId == subscriptionId)
          .toList();
      if (subServers.isEmpty) {
        CustomNotification.show(
          context,
          message: 'Для этой подписки нет конфигураций',
          type: NotificationType.error,
        );
        return;
      }

      final subscriptions = await SubscriptionService.loadSubscriptions();
      final sub = subscriptions
          .where((e) => e.id == subscriptionId)
          .firstOrNull;
      if (!mounted) return;
      final safeName = (sub?.name ?? 'subscription')
          .replaceAll(RegExp(r'[^\w\-. ]'), '_')
          .trim();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

      Directory targetDir;
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        final downloadsPath = userProfile == null
            ? null
            : '$userProfile\\Downloads';
        targetDir =
            (downloadsPath != null && Directory(downloadsPath).existsSync())
            ? Directory(downloadsPath)
            : Directory.current;
      } else {
        final home = Platform.environment['HOME'];
        final downloadsPath = home == null ? null : '$home/Downloads';
        targetDir =
            (downloadsPath != null && Directory(downloadsPath).existsSync())
            ? Directory(downloadsPath)
            : Directory.current;
      }

      final outFile = File(
        '${targetDir.path}${Platform.pathSeparator}${safeName}_$ts.txt',
      );
      final payload = subServers.map((s) => s.config.trim()).join('\n');
      await outFile.writeAsString(payload);
      if (!mounted) return;

      CustomNotification.show(
        context,
        message: 'Конфигурации сохранены: ${outFile.path}',
        type: NotificationType.success,
      );
    } catch (e) {
      CustomNotification.show(
        context,
        message: 'Ошибка сохранения конфигов: $e',
        type: NotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingSubscriptions.remove(subscriptionId));
      }
    }
  }

  @override
  Widget build(BuildContext _) {
    final grouped = <String?, List<ServerItem>>{};
    for (final server in widget.servers) {
      grouped.putIfAbsent(server.subscriptionId, () => <ServerItem>[]).add(server);
    }

    final orderedSubIds = grouped.keys
        .whereType<String>()
        .toList()
      ..sort((a, b) {
        final ai = _subscriptionOrder[a] ?? 1 << 20;
        final bi = _subscriptionOrder[b] ?? 1 << 20;
        if (ai != bi) return ai.compareTo(bi);
        final an = _subscriptionsById[a]?.name ?? '';
        final bn = _subscriptionsById[b]?.name ?? '';
        return an.compareTo(bn);
      });
    final orderedKeys = <String?>[
      ...orderedSubIds,
      if (grouped.containsKey(null)) null, // Manual servers always at bottom
    ];

    final items = <Widget>[];
    for (final subId in orderedKeys) {
      final servers = grouped[subId];
      if (servers == null || servers.isEmpty) continue;
      final collapseKey = subId ?? '__manual__';
      final isCollapsed = _collapsedGroups[collapseKey] ?? false;
      final label = subId == null
          ? context.tr('manual_servers')
          : (_subscriptionsById[subId]?.name ?? servers.first.subscriptionName ?? '');
      final trafficText = _trafficLabelForSubscription(subId);
      final expiryText = _expiryLabelForSubscription(subId);
      final canManage = subId != null;
      final bubbleChildren = <Widget>[
        _SubscriptionHeader(
          label: label,
          settings: widget.settings,
          trafficText: trafficText,
          expiryText: expiryText,
          canManage: canManage,
          isRefreshing: canManage && _refreshingSubscriptions.contains(subId),
          isDownloading: canManage && _downloadingSubscriptions.contains(subId),
          onRefresh: canManage ? () => _refreshSubscription(subId!) : null,
          onDownload:
              canManage ? () => _downloadSubscriptionConfigs(subId!) : null,
          insideBubble: true,
          isCollapsed: isCollapsed,
          onToggleCollapse: () => _toggleGroupCollapse(collapseKey),
        ),
      ];
      if (!isCollapsed) {
        for (int i = 0; i < servers.length; i++) {
          final server = servers[i];
          final isSelected = server.id == widget.controller.selectedServer?.id;
          final isConnected = isSelected && widget.controller.isConnected;
          if (i > 0) {
            bubbleChildren.add(
              _GroupDivider(settings: widget.settings),
            );
          }
          bubbleChildren.add(
            ServerListItem(
              key: ValueKey(server.id),
              server: server,
              isSelected: isSelected,
              isConnected: isConnected,
              pingResult: widget.pingManager.getPingResult(server),
              isPinging: widget.serverPingingState[server.id] ?? false,
              isAnyServerConnected: widget.controller.isConnected,
              trafficInfo: null,
              embeddedInGroup: true,
              onTap: () => widget.controller.selectServer(server),
              onFavoriteToggle: () => widget.controller.toggleFavorite(server.id),
              onPing: () => widget.onPing(server),
              onDelete: () async {
                await widget.controller.deleteServer(server.id);
                CustomNotification.show(
                  context,
                  message: 'Сервер удалён',
                  type: NotificationType.success,
                );
              },
            ),
          );
        }
      }

      items.add(
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          decoration: BoxDecoration(
            color: widget.settings.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.settings.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(children: bubbleChildren),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 20, top: 4),
      children: items,
    );
  }
}

class _GroupDivider extends StatelessWidget {
  final ThemeSettings settings;
  const _GroupDivider({required this.settings});

  @override
  Widget build(BuildContext context) {
    final c = settings.borderColor.withOpacity(settings.isDarkMode ? 0.28 : 0.36);
    return Padding(
      // Align divider with text block (after flag + spacing).
      padding: const EdgeInsets.fromLTRB(70, 0, 12, 0),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              c.withOpacity(0.0),
              c,
              c.withOpacity(0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// ─── Заголовок группы подписки ────────────────────────────────────────────────
class _SubscriptionHeader extends StatelessWidget {
  final String label;
  final ThemeSettings settings;
  final String? trafficText;
  final String? expiryText;
  final bool canManage;
  final bool isRefreshing;
  final bool isDownloading;
  final VoidCallback? onRefresh;
  final VoidCallback? onDownload;
  final bool insideBubble;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const _SubscriptionHeader({
    required this.label,
    required this.settings,
    required this.trafficText,
    required this.expiryText,
    required this.canManage,
    required this.isRefreshing,
    required this.isDownloading,
    required this.onRefresh,
    required this.onDownload,
    this.insideBubble = false,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: insideBubble
          ? const EdgeInsets.fromLTRB(12, 10, 8, 8)
          : const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          if (onToggleCollapse != null)
            _HeaderActionIcon(
              tooltip: isCollapsed ? 'Развернуть' : 'Свернуть',
              onTap: onToggleCollapse,
              icon: Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: settings.secondaryTextColor.withOpacity(0.8),
              ),
            ),
          if (onToggleCollapse != null) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: insideBubble ? 17 : 11,
                    fontWeight: FontWeight.w600,
                    color: insideBubble
                        ? settings.textColor
                        : settings.secondaryTextColor.withOpacity(0.7),
                    letterSpacing: insideBubble ? 0 : 0.8,
                  ),
                ),
                if (trafficText != null || expiryText != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      trafficText,
                      expiryText,
                    ].where((e) => e != null && e.isNotEmpty).join('  •  '),
                    style: TextStyle(
                      fontSize: 10,
                      color: settings.secondaryTextColor.withOpacity(0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            _HeaderActionIcon(
              tooltip: 'Обновить подписку',
              onTap: onRefresh,
              icon: isRefreshing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: settings.primaryColor,
                      ),
                    )
                  : Icon(
                      Icons.refresh,
                      size: 16,
                      color: settings.secondaryTextColor.withOpacity(0.75),
                    ),
            ),
            const SizedBox(width: 6),
            _HeaderActionIcon(
              tooltip: 'Скачать конфигурации',
              onTap: onDownload,
              icon: isDownloading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: settings.primaryColor,
                      ),
                    )
                  : Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: settings.secondaryTextColor.withOpacity(0.75),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderActionIcon extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HeaderActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          splashRadius: 14,
          iconSize: 16,
          icon: icon,
        ),
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
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.filledTonal(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: scheme.primaryContainer.withOpacity(0.55),
          foregroundColor: scheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimaryContainer,
                ),
              )
            : Icon(icon, size: 20),
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
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEmpty) ...[
              Icon(
                Icons.info_outline,
                size: 26,
                color: settings.secondaryTextColor,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              style: textTheme.labelMedium?.copyWith(
                color: settings.secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                body,
                style: textTheme.titleSmall?.copyWith(
                  color: settings.textColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Пустой экран ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeSettings settings;

  const _EmptyState({
    required this.icon,
    required this.text,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 60,
            color: settings.secondaryTextColor.withOpacity(0.35),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(color: settings.secondaryTextColor, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─── Волновая анимация ────────────────────────────────────────────────────────
class WaveAnimation extends StatefulWidget {
  final bool isActive;
  final bool isConnected;
  const WaveAnimation({
    super.key,
    required this.isActive,
    required this.isConnected,
  });

  @override
  State<WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<WaveAnimation>
    with WidgetsBindingObserver {
  Timer? _timer;
  double _phase = 0;
  bool _isAppResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant WaveAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncAnimationState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    _syncAnimationState();
  }

  void _syncAnimationState() {
    final shouldAnimate = widget.isActive && _isAppResumed;
    if (!shouldAnimate) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    // Run the wave at ~20 FPS to reduce background CPU/GPU.
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _phase += 0.016;
        if (_phase > 1) _phase -= 1;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    final waveColor = widget.isConnected
        ? ThemeSettings.waveColor
        : s.secondaryTextColor.withOpacity(0.45);
    return SizedBox(
      height: 28,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WavePainter(offset: _phase, color: waveColor),
          size: Size.infinite,
          isComplex: false,
          willChange: widget.isActive,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double offset;
  final Color color;
  _WavePainter({required this.offset, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const amplitude = 7.0;
    const waveLength = 60.0; // px между пиками
    path.moveTo(0, size.height / 2);
    // PERF: avoid per-pixel path segments (CPU/GPU heavy on desktop).
    // Keep roughly ~240 segments independent of window width.
    final step = (size.width / 240).clamp(2.0, 8.0);
    for (double x = 0; x <= size.width; x += step) {
      final y =
          amplitude * sin(2 * pi * (x / waveLength - offset)) + size.height / 2;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.offset != offset || oldDelegate.color != color;
}
