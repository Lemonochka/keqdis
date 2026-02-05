import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';

import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/services/tray_service.dart';
import 'package:keqdis/services/improved_subscription_service.dart';
import 'package:keqdis/core/system_proxy.dart';
import 'package:keqdis/core/tun_service.dart';
import 'package:keqdis/utils/single_instance_manager.dart';
import 'package:keqdis/utils/server_name_utils.dart';

import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'package:keqdis/screens/ping_manager.dart';

import '../widgets/power_button.dart';
import '../widgets/vpn_mode_switch.dart';
import '../widgets/server_search_bar.dart';
import '../widgets/server_list_item.dart';
import '../widgets/add_server_dialog.dart';
import '../widgets/custom_notification.dart';
import '../widgets/connection_status.dart';

import 'subscriptions_screen.dart'; // Содержит SubscriptionsView
import 'settings_screen.dart';       // Содержит SettingsView

class HomeScreen extends StatefulWidget {
  final bool isAutoStarted;

  const HomeScreen({super.key, required this.isAutoStarted});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WindowListener {

  // Сервисы
  final _trayService = TrayService();
  late final AppLifecycleListener _listener;

  // Контроллеры
  late VpnController _vpnController;
  late PingManager _pingManager;

  // ИСПРАВЛЕНИЕ: Кэш ThemeManager для предотвращения множественных вызовов
  late ThemeManager _themeManager;

  // UI состояние
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final Map<String, bool> _serverPingingState = {};

  // Настройки
  AppSettings _settings = AppSettings();
  bool _tunAvailable = false;
  bool _isReallyExiting = false;

  // Автообновление подписок
  Timer? _autoUpdateTimer;

  @override
  void initState() {
    super.initState();

    // ИСПРАВЛЕНИЕ: Инициализируем ThemeManager один раз
    _themeManager = ThemeManager();

    // Инициализация контроллеров
    _vpnController = VpnController();
    _pingManager = PingManager();

    // Window listener
    windowManager.addListener(this);
    _listener = AppLifecycleListener(onExitRequested: _onAppExit);
    windowManager.setPreventClose(true);

    // Инициализация приложения
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Загрузка данных
      await Future.wait([
        _vpnController.loadInitialServers(),
        _loadSettings(),
      ]);

      // Проверка TUN
      await _checkTunAvailability();

      // Инициализация трея
      await _initializeTray();

      // Слушатель для обновления трея
      _vpnController.addListener(_updateTrayStatus);

      // Автообновление подписок
      _startSubscriptionAutoUpdate();

      // Автоподключение
      if (_settings.autoConnectLastServer) {
        await _vpnController.autoConnectToLastServer();
      }
    } catch (e) {
      debugPrint('Ошибка инициализации: $e');
    }
  }

  // ИСПРАВЛЕНИЕ: Метод для обновления статуса трея
  void _updateTrayStatus() {
    _trayService.updateConnectionStatus(_vpnController.isConnected);
  }

  Future<void> _loadSettings() async {
    _settings = await SettingsStorage.loadSettings();
    if (mounted) setState(() {});
  }

  Future<void> _checkTunAvailability() async {
    final available = await TunService.isTunAvailable();
    if (mounted) {
      setState(() => _tunAvailable = available);
    }
  }

  Future<void> _initializeTray() async {
    await _trayService.initialize(
      onShowCallback: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      onToggleCallback: () => _vpnController.toggleConnection(),
      onExitCallback: _exitApp,
    );
  }

  void _startSubscriptionAutoUpdate() {
    _autoUpdateTimer = Timer.periodic(
      const Duration(hours: 12),
          (_) async {
        try {
          final dueSubscriptions =
          await SubscriptionService.getSubscriptionsDueForUpdate(
            interval: const Duration(hours: 12),
          );

          if (dueSubscriptions.isNotEmpty) {
            await SubscriptionService.updateAllSubscriptions();
            await _vpnController.loadInitialServers();
          }
        } catch (e) {
          debugPrint('Ошибка автообновления: $e');
        }
      },
    );
  }

  @override
  void dispose() {
    // ИСПРАВЛЕНИЕ: Удаляем слушателя, чтобы избежать утечек памяти
    _vpnController.removeListener(_updateTrayStatus);
    windowManager.removeListener(this);
    _listener.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _autoUpdateTimer?.cancel();
    _vpnController.dispose();
    _pingManager.dispose();
    SingleInstanceManager.release();
    super.dispose();
  }

  Future<AppExitResponse> _onAppExit() async {
    if (!_isReallyExiting && _settings.minimizeToTray) {
      await windowManager.hide();
      return AppExitResponse.cancel;
    }

    await _exitApp();
    return AppExitResponse.exit;
  }

  Future<void> _exitApp() async {
    setState(() => _isReallyExiting = true);
    await SystemProxy.clearProxy();
    await _vpnController.disconnect();
    await _trayService.dispose();
    await SingleInstanceManager.release();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() async {
    if (_isReallyExiting) {
      await windowManager.destroy();
      return;
    }

    if (_settings.minimizeToTray) {
      await windowManager.hide();
    } else {
      _showExitConfirmDialog();
    }
  }

  void _showExitConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _themeManager.settings.accentColor,
        title: const Text('Выход'),
        content: const Text('Вы действительно хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _exitApp();
            },
            child: const Text('Выход'),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _vpnController.searchServers(query);
    });
  }

  Future<void> _handleVpnModeSwitch(VpnMode newMode) async {
    if (newMode == VpnMode.tun && !await TunService.hasAdminRights()) {
      _showAdminRequiredDialog();
      return;
    }

    if (_vpnController.isConnected) {
      try {
        await _vpnController.disconnect();
        _vpnController.switchVpnMode(newMode);
        await _vpnController.toggleConnection();

        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Режим изменен на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
            type: NotificationType.success,
          );
        }
      } catch (e) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Ошибка смены режима: $e',
            type: NotificationType.error,
          );
        }
      }
    } else {
      _vpnController.switchVpnMode(newMode);
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Режим изменен на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
          type: NotificationType.success,
        );
      }
    }
  }

  void _showAdminRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _themeManager.settings.accentColor,
        title: Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: _themeManager.settings.primaryColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Требуются права администратора'),
            ),
          ],
        ),
        content: const Text(
          'Для использования TUN режима необходимо запустить приложение от имени администратора.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _restartAsAdmin();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Перезапустить с правами администратора'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeManager.settings.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restartAsAdmin() async {
    try {
      if (Platform.isWindows) {
        // Получаем путь к исполняемому файлу
        final exePath = Platform.resolvedExecutable;

        // Запускаем процесс с правами администратора через PowerShell
        await Process.start(
          'powershell',
          [
            '-Command',
            'Start-Process',
            '-FilePath',
            '"$exePath"',
            '-Verb',
            'RunAs',
          ],
          mode: ProcessStartMode.detached,
        );

        // Даем время на запуск нового процесса
        await Future.delayed(const Duration(milliseconds: 500));

        // Закрываем текущее приложение
        await _exitApp();
      } else {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Перезапуск с правами администратора доступен только на Windows',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка перезапуска: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _pingServer(ServerItem server) async {
    if (_serverPingingState[server.id] ?? false) return;

    setState(() => _serverPingingState[server.id] = true);

    try {
      await _pingManager.pingServer(server, _settings.pingType);
    } finally {
      if (mounted) {
        setState(() => _serverPingingState[server.id] = false);
      }
    }
  }

  Future<void> _pingAllServers(List<ServerItem> servers) async {
    await _pingManager.pingMultipleServers(servers, _settings.pingType, (server, isComplete) {
      // Можно добавить логику для отслеживания прогресса, если нужно
    });
  }

  void _showAddServerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AddServerDialog(
        onServersAdded: (configs) async {
          int successCount = 0;
          for (final config in configs) {
            try {
              await _vpnController.addServer(config);
              successCount++;
            } catch (e) {
              debugPrint('Ошибка добавления сервера: $e');
            }
          }

          if (mounted) {
            CustomNotification.show(
              context,
              message: 'Добавлено серверов: $successCount из ${configs.length}',
              type: NotificationType.success,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _vpnController),
        ChangeNotifierProvider.value(value: _pingManager),
      ],
      child: Scaffold(
        body: Stack(
          children: [
            // Кастомный фон (если есть)
            if (_themeManager.hasCustomBackground)
              Positioned.fill(
                child: _buildOptimizedBackground(context),
              ),

            // Основной контент
            Row(
              children: [
                // ОБНОВЛЕНО: Левая колонка с прозрачностью
                _buildSidebar(),

                // Вертикальный разделитель
                Container(
                  width: 1,
                  color: Colors.white.withAlpha(26), // 0.1 opacity
                ),

                // Основная область
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizedBackground(BuildContext context) {
    final path = _themeManager.settings.backgroundImagePath!;
    final imageProvider = FileImage(File(path));

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio).round();
    final screenHeight = (mediaQuery.size.height * mediaQuery.devicePixelRatio).round();

    final resizedImageProvider = ResizeImage(
      imageProvider,
      width: screenWidth,
      height: screenHeight,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: resizedImageProvider,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Ошибка загрузки фонового изображения: $error');
            Future.microtask(() => _themeManager.removeBackground());
            return Container(color: const Color(0xFF0A0E27));
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _themeManager.settings.blurIntensity,
            sigmaY: _themeManager.settings.blurIntensity,
          ),
          child: Container(
            color: Colors.black.withAlpha(
              (255 * (1.0 - _themeManager.settings.backgroundOpacity)).round(),
            ),
          ),
        ),
      ],
    );
  }

  // ОБНОВЛЕНО: Левая колонка с прозрачностью
  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        // Добавляем полупрозрачный фон
        color: _themeManager.settings.accentColor.withAlpha(77), // 0.3 opacity
        border: Border(
          right: BorderSide(
            color: Colors.white.withAlpha(13), // 0.05 opacity
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Статус подключения (перемещен наверх)
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

          // Навигационные кнопки
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavButton(
                  icon: Icons.dns,
                  label: 'Серверы',
                  isSelected: _currentTab == 0,
                  onTap: () => setState(() => _currentTab = 0),
                ),
                _buildNavButton(
                  icon: Icons.rss_feed,
                  label: 'Подписки',
                  isSelected: _currentTab == 1,
                  onTap: () => setState(() => _currentTab = 1),
                ),
                _buildNavButton(
                  icon: Icons.settings,
                  label: 'Настройки',
                  isSelected: _currentTab == 2,
                  onTap: () => setState(() => _currentTab = 2),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Версия
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'v1.0.0',
              style: TextStyle(
                color: Colors.white.withAlpha(77), // 0.3 opacity
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
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
                  ? _themeManager.settings.primaryColor.withAlpha(51) // 0.2 opacity
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                color: _themeManager.settings.primaryColor.withAlpha(128), // 0.5 opacity
                width: 1,
              )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? _themeManager.settings.primaryColor
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

  Widget _buildMainContent() {
    switch (_currentTab) {
      case 0:
        return _buildServerList();
      case 1:
        return SubscriptionsView(
          onServersUpdated: () async {
            await _vpnController.loadInitialServers();
          },
        );
      case 2:
        return SettingsView(
          onSettingsChanged: () async {
            await _loadSettings();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServerList() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Левая часть - поиск и список серверов
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Поиск
              Padding(
                padding: const EdgeInsets.all(16),
                child: ServerSearchBar(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchController.clear();
                    _vpnController.searchServers('');
                  },
                ),
              ),

              // Компактные кнопки
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Кнопка добавления
                    Tooltip(
                      message: 'Добавить сервер',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _themeManager.settings.accentColor.withAlpha(77), // 0.3 opacity
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _themeManager.settings.primaryColor.withAlpha(77), // 0.3 opacity
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          onPressed: _showAddServerDialog,
                          icon: Icon(
                            Icons.add_rounded,
                            color: _themeManager.settings.primaryColor,
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Кнопка пинга всех
                    Consumer<PingManager>(
                      builder: (context, pingManager, _) => Tooltip(
                        message: 'Пинг всех серверов',
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _themeManager.settings.accentColor.withAlpha(77), // 0.3 opacity
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _themeManager.settings.primaryColor.withAlpha(77), // 0.3 opacity
                              width: 1,
                            ),
                          ),
                          child: IconButton(
                            onPressed: pingManager.isPinging
                                ? null
                                : () => _pingAllServers(
                                _vpnController.searchResults.isNotEmpty
                                    ? _vpnController.searchResults
                                    : _vpnController.allServers
                            ),
                            icon: pingManager.isPinging
                                ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _themeManager.settings.primaryColor,
                              ),
                            )
                                : Icon(
                              Icons.speed_rounded,
                              color: _themeManager.settings.primaryColor,
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

              // Список серверов
              Expanded(
                child: Consumer2<VpnController, PingManager>(
                  builder: (context, controller, pingManager, _) {
                    final servers = _searchController.text.isNotEmpty
                        ? controller.searchResults
                        : controller.allServers;

                    if (servers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchController.text.isEmpty ? Icons.dns_outlined : Icons.search_off,
                              size: 64,
                              color: Colors.white.withAlpha(77),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
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
                        final isPinging = _serverPingingState[server.id] ?? false;

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
                          onPing: () => _pingServer(server),
                          onDelete: () async {
                            await controller.deleteServer(server.id);
                            if (mounted) {
                              CustomNotification.show(
                                context,
                                message: 'Сервер удален',
                                type: NotificationType.success,
                              );
                            }
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

        // Правая колонка - панель управления (на всю высоту)
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: _themeManager.settings.accentColor.withAlpha(77), // 0.3 opacity
            border: Border(
              left: BorderSide(
                color: Colors.white.withAlpha(13), // 0.05 opacity
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Пустое пространство сверху для центрирования кнопки
              const Spacer(),

              // Кнопка питания (в центре)
              Consumer<VpnController>(
                builder: (context, controller, _) => PowerButton(
                  isConnected: controller.isConnected,
                  isConnecting: controller.isConnecting,
                  onTap: controller.toggleConnection,
                ),
              ),

              const SizedBox(height: 24),

              // Информация о выбранном сервере (под кнопкой)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer<VpnController>(
                  builder: (context, controller, _) {
                    if (controller.selectedServer == null) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _themeManager.settings.accentColor.withAlpha(51), // 0.2 opacity
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withAlpha(26), // 0.1 opacity
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
                        color: _themeManager.settings.accentColor.withAlpha(51), // 0.2 opacity
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withAlpha(26), // 0.1 opacity
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

              // Пустое пространство для отталкивания VPN Mode Switch вниз
              const Spacer(),

              // VPN Mode Switch (внизу)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Consumer<VpnController>(
                  builder: (context, controller, _) => VpnModeSwitch(
                    currentMode: controller.vpnMode,
                    tunAvailable: _tunAvailable,
                    isConnected: controller.isConnected,
                    onModeChanged: _handleVpnModeSwitch,
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