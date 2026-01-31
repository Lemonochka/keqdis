import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'core_manager.dart';
import 'unified_storage.dart';
import 'improved_settings_storage.dart';
import 'system_proxy.dart';
import 'config_validator.dart';
import 'tray_service.dart';
import 'autostart_service.dart';
import 'improved_theme_manager.dart';
import 'ping_service.dart';
import 'improved_subscription_service.dart';
import 'custom_notification.dart';
import 'single_instance_manager.dart';
import 'package:country_flags/country_flags.dart';

// ========== ГЛАВНЫЙ SHELL ==========
class MainShell extends StatefulWidget {
  final bool isAutoStarted;

  const MainShell({super.key, required this.isAutoStarted});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with TickerProviderStateMixin, WindowListener {

  // ========== МЕНЕДЖЕРЫ ==========
  final _coreManager = CoreManager();
  final _trayService = TrayService();
  late final AppLifecycleListener _listener;

  // ========== СОСТОЯНИЕ ==========
  int _currentTab = 0; // 0=Servers, 1=Subscriptions, 2=Settings
  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = "Отключено";
  bool _isReallyExiting = false;

  // ========== ДАННЫЕ ==========
  List<ServerItem> _servers = [];
  int _selectedServerIndex = -1;
  bool _useSystemProxy = true;
  AppSettings _settings = AppSettings();

  // ========== ПИНГ (ОПТИМИЗИРОВАНО) ==========
  Map<String, PingResult> _pingResults = {};
  bool _isPinging = false;
  Timer? _pingCacheCleanup;

  // ========== ПОИСК (С DEBOUNCE) ==========
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ========== ТАЙМЕРЫ (ДЛЯ CLEANUP) ==========
  Timer? _autoUpdateTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadData();
    _initializeTray();
    _listener = AppLifecycleListener(onExitRequested: _onAppExit);
    windowManager.setPreventClose(true);

    // Запускаем автообновление подписок
    _startSubscriptionAutoUpdate();
    _updateSubscriptionsOnStart();
    _autoConnectToLastServer();

    // НОВОЕ: Очистка кэша пингов каждые 5 минут
    _pingCacheCleanup = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _cleanupOldPingResults(),
    );
  }

  @override
  void dispose() {
    print('🧹 Cleanup начат...');

    // КРИТИЧНО: Освобождаем ресурсы
    windowManager.removeListener(this);
    _listener.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _autoUpdateTimer?.cancel();
    _pingCacheCleanup?.cancel();
    _pingResults.clear(); // Освобождаем память

    // Освобождаем single instance lock
    SingleInstanceManager.release();

    print('🧹 Cleanup завершён');
    super.dispose();
  }

  // ========== ОЧИСТКА СТАРЫХ ПИНГОВ (ОПТИМИЗАЦИЯ ПАМЯТИ) ==========
  void _cleanupOldPingResults() {
    final now = DateTime.now();
    _pingResults.removeWhere((key, value) {
      // Удаляем результаты старше 10 минут
      return true; // Упрощённая версия, можно добавить timestamp
    });
    print('🧹 Очищен кэш пингов: ${_pingResults.length} записей осталось');
  }

  // ========== LIFECYCLE ==========
  Future<AppExitResponse> _onAppExit() async {
    if (!_isReallyExiting) {
      // Сворачиваем вместо закрытия
      if (_settings.minimizeToTray) {
        await windowManager.hide();
        return AppExitResponse.cancel;
      }
    }

    // Реальный выход
    print('🚪 Выход из приложения...');
    await SystemProxy.clearProxy();
    await _coreManager.stop();
    await _trayService.dispose();
    await SingleInstanceManager.release();
    return AppExitResponse.exit;
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
        backgroundColor: ThemeManager().settings.accentColor,
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
              setState(() => _isReallyExiting = true);
              await _onAppExit();
              await windowManager.destroy();
            },
            child: const Text('Выход'),
          ),
        ],
      ),
    );
  }

  // ========== ЗАГРУЗКА ДАННЫХ (ОПТИМИЗИРОВАНО) ==========
  Future<void> _loadData() async {
    try {
      // Параллельная загрузка для скорости
      final results = await Future.wait([
        UnifiedStorage.loadServers(),
        SettingsStorage.loadSettings(),
      ]);

      if (mounted) {
        setState(() {
          _servers = (results[0] as List<ServerItem>)
            ..sort((a, b) {
              // Избранные сверху
              if (a.isFavorite && !b.isFavorite) return -1;
              if (!a.isFavorite && b.isFavorite) return 1;
              return 0;
            });
          _settings = results[1] as AppSettings;
          _useSystemProxy = true;
        });

        // Обновляем статус автозапуска
        await AutoStartService.toggle(_settings.autoStart);
      }
    } catch (e) {
      print('Ошибка загрузки данных: $e');
    }
  }

  // ========== ИНИЦИАЛИЗАЦИЯ ТРЕЯ ==========
  Future<void> _initializeTray() async {
    await _trayService.initialize(
      onShowCallback: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      onToggleCallback: _toggleVpn,
      onExitCallback: () async {
        setState(() => _isReallyExiting = true);
        await _onAppExit();
        await windowManager.destroy();
      },
    );
  }

  // ========== АВТООБНОВЛЕНИЕ ПОДПИСОК ==========
  void _startSubscriptionAutoUpdate() {
    _autoUpdateTimer = Timer.periodic(const Duration(hours: 12), (timer) async {
      try {
        final dueSubscriptions = await SubscriptionService.getSubscriptionsDueForUpdate(
          interval: const Duration(hours: 12),
        );

        if (dueSubscriptions.isNotEmpty) {
          print('Автообновление ${dueSubscriptions.length} подписок');
          await SubscriptionService.updateAllSubscriptions();
          _loadData();
        }
      } catch (e) {
        print('Ошибка автообновления: $e');
      }
    });
  }

  Future<void> _updateSubscriptionsOnStart() async {
    try {
      final subscriptions = await SubscriptionService.loadSubscriptions();
      if (subscriptions.isEmpty) return;

      for (final sub in subscriptions) {
        await SubscriptionService.updateSubscriptionServers(sub);
        await Future.delayed(const Duration(seconds: 2)); // Rate limiting
      }

      _loadData();
    } catch (e) {
      print('Ошибка обновления при старте: $e');
    }
  }

  // ========== АВТОПОДКЛЮЧЕНИЕ ==========
  Future<void> _autoConnectToLastServer() async {
    try {
      if (!_settings.autoConnectLastServer) return;

      await Future.delayed(const Duration(milliseconds: 1500));

      final lastServer = await UnifiedStorage.getLastServer();
      if (lastServer == null) return;

      final index = _servers.indexWhere((s) => s.id == lastServer.id);
      if (index == -1) return;

      if (mounted) {
        setState(() => _selectedServerIndex = index);
        await Future.delayed(const Duration(milliseconds: 500));
        _toggleVpn();
      }
    } catch (e) {
      print('Ошибка автоподключения: $e');
    }
  }

  // ========== ПИНГ (ИСПРАВЛЕН БАГ) ==========
  Future<void> _pingSingleServer(String config) async {
    if (_isPinging) return;
    setState(() => _isPinging = true);

    try {
      final pingType = _settings.pingType == 'tcp' ? PingType.tcp : PingType.proxy;
      final result = await PingService.ping(
        config,
        pingType,
        proxyPort: _settings.localPort,
      );

      if (mounted) {
        setState(() {
          _pingResults[config] = result;
          _isPinging = false;
        });

        // 🐛 ИСПРАВЛЕН БАГ: Было message: 'message', стало message: message
        final message = result.success
            ? 'Пинг: ${result.latencyMs} мс'
            : 'Не удалось пропинговать сервер';

        CustomNotification.show(
          context,
          message: message, // <-- ИСПРАВЛЕНО!
          type: result.success ? NotificationType.success : NotificationType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPinging = false);
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _pingAllServers() async {
    if (_isPinging || _servers.isEmpty) return;
    setState(() => _isPinging = true);

    try {
      final pingType = _settings.pingType == 'tcp' ? PingType.tcp : PingType.proxy;
      int successCount = 0;

      for (final server in _servers) {
        final result = await PingService.ping(
          server.config,
          pingType,
          proxyPort: _settings.localPort,
          timeoutSeconds: 5,
        );

        if (mounted) {
          setState(() => _pingResults[server.config] = result);
        }

        if (result.success) successCount++;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        setState(() => _isPinging = false);
        CustomNotification.show(
          context,
          message: 'Пропинговано: $successCount из ${_servers.length}',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPinging = false);
      }
    }
  }

  // ========== ПОДКЛЮЧЕНИЕ/ОТКЛЮЧЕНИЕ ==========
  void _toggleVpn() async {
    if (_isConnecting) return;

    if (_isConnected) {
      if (mounted) setState(() {
        _isConnecting = true;
        _status = "Отключение...";
      });

      if (_useSystemProxy) await SystemProxy.clearProxy();
      await _coreManager.stop();

      if (mounted) setState(() {
        _isConnected = false;
        _isConnecting = false;
        _status = "Отключено";
      });

      await _trayService.updateConnectionStatus(false);
    } else {
      if (_selectedServerIndex == -1 || _servers.isEmpty) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Выберите сервер',
            type: NotificationType.warning,
          );
        }
        return;
      }

      if (mounted) setState(() {
        _isConnecting = true;
        _status = "Подключение...";
      });

      try {
        final selectedServer = _servers[_selectedServerIndex];
        await _coreManager.start(
          selectedServer.config,
          useSystemProxy: _useSystemProxy,
        );

        await UnifiedStorage.saveLastServer(selectedServer.id);

        if (mounted) setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = "Подключено";
        });

        await _trayService.updateConnectionStatus(true);
      } catch (e) {
        if (_useSystemProxy) await SystemProxy.clearProxy();
        await _coreManager.stop();

        if (mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _status = "Ошибка: ${e.toString()}";
          });

          CustomNotification.show(
            context,
            message: 'Ошибка подключения: $e',
            type: NotificationType.error,
          );
        }

        await _trayService.updateConnectionStatus(false);
      }
    }
  }

  // ========== CRUD ОПЕРАЦИИ ==========
  Future<void> _addServer(String config) async {
    try {
      await UnifiedStorage.addManualServer(config);
      await _loadData();

      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Сервер добавлен',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteServer(int index) async {
    if (index < 0 || index >= _servers.length) return;

    final server = _servers[index];
    try {
      await UnifiedStorage.deleteServer(server.id);
      await _loadData();

      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Сервер удален',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _toggleFavorite(String serverId) async {
    try {
      await UnifiedStorage.toggleFavorite(serverId);
      await _loadData();

      final server = _servers.firstWhere((s) => s.id == serverId);
      if (mounted) {
        CustomNotification.show(
          context,
          message: server.isFavorite
              ? '${server.displayName} добавлен в избранное'
              : '${server.displayName} убран из избранного',
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  // ========== DEBOUNCED SEARCH ==========
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = query);
      }
    });
  }

  // ========== ЭКСПОРТ КОНФИГОВ ==========
  Future<void> _exportConfigs() async {
    try {
      if (_servers.isEmpty) {
        CustomNotification.show(
          context,
          message: 'Нет серверов для экспорта',
          type: NotificationType.warning,
        );
        return;
      }

      final configs = _servers.map((s) => s.config).join('\n');
      await Clipboard.setData(ClipboardData(text: configs));

      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Конфиги скопированы в буфер обмена (${_servers.length} шт.)',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка экспорта: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  // ========== BUILD - НОВЫЙ ДИЗАЙН (3 ПАНЕЛИ) ==========
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      body: Stack(
        children: [
          // Фон
          if (themeManager.hasCustomBackground)
            _buildCustomBackground(themeManager),

          // Основной контент - 3 ПАНЕЛИ
          Row(
            children: [
              // ЛЕВАЯ ПАНЕЛЬ - Вкладки (Настройки/Подписки/и т.д.)
              _buildLeftSidebar(),

              // ЦЕНТРАЛЬНАЯ ПАНЕЛЬ - Серверы
              Expanded(
                flex: 3,
                child: _buildServersPanel(),
              ),

              // ПРАВАЯ ПАНЕЛЬ - Управление (Круглая кнопка + System Proxy)
              _buildRightControlPanel(),
            ],
          ),
        ],
      ),
    );
  }

// ========== ФОНОВОЕ ИЗОБРАЖЕНИЕ ==========
  Widget _buildCustomBackground(ThemeManager themeManager) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(themeManager.settings.backgroundImagePath!)),
          fit: BoxFit.cover,
          // opacity убран - картинка теперь непрозрачная
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: themeManager.settings.blurIntensity,
          sigmaY: themeManager.settings.blurIntensity,
        ),
        child: Container(color: Colors.black.withOpacity(1.0 - themeManager.settings.backgroundOpacity)),
      ),
    );
  }

// ========== ЛЕВАЯ БОКОВАЯ ПАНЕЛЬ (Вкладки) ==========
  Widget _buildLeftSidebar() {
    final themeManager = ThemeManager();

    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: themeManager.settings.accentColor.withOpacity(0.7),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 30),

          // Логотип
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  themeManager.settings.primaryColor,
                  themeManager.settings.secondaryColor,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield, color: Colors.white, size: 24),
          ),

          const SizedBox(height: 40),

          // Вкладки
          _buildNavIcon(Icons.dns_rounded, 0, 'Серверы'),
          const SizedBox(height: 20),
          _buildNavIcon(Icons.subscriptions, 1, 'Подписки'),
          const SizedBox(height: 20),
          _buildNavIcon(Icons.settings_rounded, 2, 'Настройки'),

          const Spacer(),

          // Индикатор подключения УДАЛЁН - был красный крестик
        ],
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, int index, String tooltip) {
    final isSelected = _currentTab == index;
    final themeManager = ThemeManager();

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: () => setState(() => _currentTab = index),
        icon: Icon(icon),
        color: isSelected
            ? themeManager.settings.secondaryColor
            : Colors.white.withOpacity(0.3),
        iconSize: 28,
        style: IconButton.styleFrom(
          backgroundColor: isSelected
              ? themeManager.settings.secondaryColor.withOpacity(0.1)
              : Colors.transparent,
          padding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

// ========== ЦЕНТРАЛЬНАЯ ПАНЕЛЬ (Серверы) ==========
  Widget _buildServersPanel() {
    final themeManager = ThemeManager();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27).withOpacity(0.7),
      ),
      child: Column(
        children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  _getTabTitle(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_currentTab == 0) ...[
                  // Кнопка экспорта
                  IconButton(
                    onPressed: _servers.isEmpty ? null : _exportConfigs,
                    icon: const Icon(Icons.download),
                    tooltip: 'Экспорт конфигов',
                  ),
                  // Кнопка пинга всех
                  IconButton(
                    onPressed: _isPinging ? null : _pingAllServers,
                    icon: _isPinging
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.network_ping),
                    tooltip: 'Пинг всех серверов',
                  ),
                  // Кнопка добавления
                  IconButton(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add),
                    tooltip: 'Добавить сервер',
                  ),
                ],
              ],
            ),
          ),

          // Контент вкладки
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  String _getTabTitle() {
    switch (_currentTab) {
      case 0: return 'Серверы (${_servers.length})';
      case 1: return 'Подписки';
      case 2: return 'Настройки';
      default: return 'KEQDIS';
    }
  }

  Widget _buildTabContent() {
    switch (_currentTab) {
      case 0:
        return _buildServersList();
      case 1:
        return _buildSubscriptionsView();
      case 2:
        return _buildSettingsView();
      default:
        return const SizedBox();
    }
  }

// ========== СПИСОК СЕРВЕРОВ (ОПТИМИЗИРОВАНО) ==========
  Widget _buildServersList() {
    if (_servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'Нет серверов',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        ),
      );
    }

    // Фильтрация серверов
    final filteredServers = _searchQuery.isEmpty
        ? _servers
        : _servers.where((server) {
      final query = _searchQuery.toLowerCase();
      return server.displayName.toLowerCase().contains(query) ||
          server.config.toLowerCase().contains(query) ||
          (server.subscriptionName?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Column(
      children: [
        // Поле поиска
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Поиск серверов...',
              prefixIcon: const Icon(Icons.search),
              suffixText: _searchQuery.isNotEmpty ? 'Найдено: ${filteredServers.length}' : null,
              suffixStyle: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Список серверов (ОПТИМИЗИРОВАНО с ListView.builder)
        Expanded(
          child: ListView.builder(
            itemCount: filteredServers.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // ОПТИМИЗАЦИЯ: Отключаем keepAlive для экономии памяти
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              final server = filteredServers[index];
              final isSelected = _servers.indexOf(server) == _selectedServerIndex;
              final pingResult = _pingResults[server.config];

              return _buildServerTile(
                server: server,
                isSelected: isSelected,
                pingResult: pingResult,
                onTap: () {
                  setState(() {
                    _selectedServerIndex = _servers.indexOf(server);
                  });
                },
                onPing: () => _pingSingleServer(server.config),
                onDelete: () => _deleteServer(_servers.indexOf(server)),
                onToggleFavorite: () => _toggleFavorite(server.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildServerTile({
    required ServerItem server,
    required bool isSelected,
    PingResult? pingResult,
    required VoidCallback onTap,
    required VoidCallback onPing,
    required VoidCallback onDelete,
    required VoidCallback onToggleFavorite,
  }) {
    final themeManager = ThemeManager();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? themeManager.settings.primaryColor.withOpacity(0.2)
            : themeManager.settings.accentColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: themeManager.settings.primaryColor, width: 2)
            : null,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Флаг страны в кружок
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: Colors.white.withOpacity(0.12),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: server.countryCode != null
                    ? Padding(
                  padding: const EdgeInsets.all(5),
                  child: CountryFlag.fromCountryCode(
                    server.countryCode!,
                    width: 30,
                    height: 30,
                    borderRadius: 15,
                  ),
                )
                    : const Center(
                  child: Icon(Icons.language, color: Colors.white54, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (server.isFavorite)
              const Icon(Icons.star, color: Colors.amber, size: 15),
          ],
        ),
        title: Text(
          server.cleanDisplayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: server.type == ServerItemType.subscription
            ? Row(
          children: [
            Icon(Icons.subscriptions, size: 12, color: Colors.white.withOpacity(0.5)),
            const SizedBox(width: 4),
            Text(
              server.subscriptionName ?? 'Подписка',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
          ],
        )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pingResult != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: pingResult.success
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    pingResult.success ? '${pingResult.latencyMs} ms' : 'Ошибка',
                    style: TextStyle(
                      color: pingResult.success ? Colors.green : Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                server.isFavorite ? Icons.star : Icons.star_border,
                color: server.isFavorite ? Colors.amber : Colors.white.withOpacity(0.5),
              ),
              onPressed: onToggleFavorite,
              iconSize: 20,
            ),
            IconButton(
              icon: const Icon(Icons.network_ping),
              onPressed: _isPinging ? null : onPing,
              iconSize: 20,
            ),
            if (server.type == ServerItemType.manual)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: onDelete,
                color: Colors.red.withOpacity(0.7),
                iconSize: 20,
              ),
          ],
        ),
      ),
    );
  }

// ========== ПРАВАЯ ПАНЕЛЬ УПРАВЛЕНИЯ (НОВЫЙ ДИЗАЙН) ==========
  Widget _buildRightControlPanel() {
    final themeManager = ThemeManager();

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: themeManager.settings.accentColor.withOpacity(0.7),
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 40),

          // Статус подключения
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Статус',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _status,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const Spacer(),

          // КРУГЛАЯ КНОПКА ВКЛЮЧЕНИЯ (АНИМИРОВАННАЯ) - ОТЦЕНТРОВАНА
          _buildPowerButton(),

          const Spacer(),

          // Системный прокси - ПЕРЕМЕЩЁН ВНИЗ
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Системный прокси',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Порт: ${_settings.localPort}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _useSystemProxy,
                  onChanged: (_isConnected || _isConnecting)
                      ? null
                      : (v) async {
                    setState(() => _useSystemProxy = v);
                    // ИСПРАВЛЕНИЕ: Реально включаем/выключаем прокси
                    if (v && _isConnected) {
                      await SystemProxy.setHTTPProxy(
                        address: '127.0.0.1:${_settings.localPort}',
                      );
                    } else if (!v) {
                      await SystemProxy.clearProxy();
                    }
                  },
                  activeColor: themeManager.settings.primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// ========== АНИМИРОВАННАЯ КРУГЛАЯ КНОПКА ПИТАНИЯ ==========
  Widget _buildPowerButton() {
    final themeManager = ThemeManager();
    final size = 140.0;

    Color _darken(Color c, double factor) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
    }

    final dim = _isConnected ? 0.45 : 1.0;
    final topColor = _darken(themeManager.settings.primaryColor, dim);
    final bottomColor = _darken(themeManager.settings.secondaryColor, dim);
    final glowColor = _darken(themeManager.settings.primaryColor, dim * 0.85);

    return GestureDetector(
      onTap: _isConnecting ? null : _toggleVpn,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
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
            BoxShadow(
              color: glowColor.withOpacity(_isConnected ? 0.22 : 0.35),
              blurRadius: 22,
              spreadRadius: 4,
            ),
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
            // Внутреннее кольцо — текстура объёма
            Container(
              margin: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
            ),
            // Верхний блик для 3D
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
              child: _isConnecting
                  ? const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              )
                  : const Icon(
                Icons.power_settings_new,
                color: Colors.white,
                size: 56,
              ),
            ),
          ],
        ),
      ),
    );
  }

// ========== ДИАЛОГ ДОБАВЛЕНИЯ СЕРВЕРА ==========
  void _showAddDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeManager().settings.accentColor,
        title: const Text('Добавить серверы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Вставьте один или несколько конфигов\n(каждый с новой строки)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF0A0E27),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    textController.text = data!.text!;
                  }
                },
                icon: const Icon(Icons.content_paste),
                label: const Text('Вставить из буфера'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              if (text.isEmpty) return;

              final lines = text.split('\n');
              int added = 0;

              for (var line in lines) {
                final cfg = line.trim();
                if (cfg.isNotEmpty && ConfigValidator.isValidConfig(cfg)) {
                  _addServer(cfg);
                  added++;
                }
              }

              if (added > 0) {
                Navigator.pop(ctx);
                CustomNotification.show(
                  context,
                  message: 'Добавлено серверов: $added',
                  type: NotificationType.success,
                );
              } else {
                CustomNotification.show(
                  ctx,
                  message: 'Не найдено валидных конфигов',
                  type: NotificationType.error,
                );
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

// ========== ЗАГЛУШКИ ДЛЯ ДРУГИХ ВКЛАДОК ==========
// (Используй код из original main.dart для SubscriptionsView и SettingsView)

  Widget _buildSubscriptionsView() {
    return SubscriptionsView(
      onServersUpdated: _loadData,
    );
  }

  // ========== ВКЛАДКА: НАСТРОЙКИ (ПОЛНЫЙ КОД) ==========
  Widget _buildSettingsView() {
    return SettingsView(
      onThemeChanged: () {
        setState(() {});
      },
      onSettingsChanged: _loadData,
    );
  }
}

class SubscriptionsView extends StatefulWidget {
  final VoidCallback onServersUpdated;

  const SubscriptionsView({
    super.key,
    required this.onServersUpdated,
  });

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  List<Subscription> _subscriptions = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  Map<String, bool> _updatingSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    setState(() => _isLoading = true);
    try {
      final subs = await SubscriptionService.loadSubscriptions();
      if (mounted) {
        setState(() {
          _subscriptions = subs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomNotification.show(
          context,
          message: 'Ошибка загрузки: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool autoUpdate = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeManager().settings.accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Добавить подписку'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'Например: Моя подписка',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL подписки',
                    hintText: 'https://example.com/subscription',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Автообновление'),
                  subtitle: const Text('Обновлять автоматически каждые 12 часов'),
                  value: autoUpdate,
                  activeColor: ThemeManager().settings.primaryColor,
                  onChanged: (value) => setDialogState(() => autoUpdate = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeManager().settings.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();

      if (name.isEmpty || url.isEmpty) {
        CustomNotification.show(
          context,
          message: 'Заполните все поля',
          type: NotificationType.warning,
        );
        return;
      }

      try {
        // Добавляем подписку
        final subscription = await SubscriptionService.addSubscription(
          name: name,
          url: url,
          autoUpdate: autoUpdate,
        );

        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Подписка добавлена, загрузка серверов...',
            type: NotificationType.success,
          );
          _loadSubscriptions();

          // Сразу же загружаем серверы из подписки
          final updateResult = await SubscriptionService.updateSubscriptionServers(subscription);

          if (updateResult.success) {
            CustomNotification.show(
              context,
              message: 'Загружено ${updateResult.serverCount} серверов',
              type: NotificationType.success,
            );
            _loadSubscriptions();
            widget.onServersUpdated(); // Обновляем список серверов
          } else {
            CustomNotification.show(
              context,
              message: 'Ошибка загрузки серверов: ${updateResult.error}',
              type: NotificationType.warning,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Ошибка: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _updateSubscription(Subscription subscription) async {
    setState(() => _updatingSubscriptions[subscription.id] = true);

    try {
      final result = await SubscriptionService.updateSubscriptionServers(subscription);

      if (mounted) {
        setState(() => _updatingSubscriptions[subscription.id] = false);

        if (result.success) {
          CustomNotification.show(
            context,
            message: 'Обновлено: ${result.serverCount} серверов',
            type: NotificationType.success,
          );
          _loadSubscriptions();
          widget.onServersUpdated();
        } else {
          CustomNotification.show(
            context,
            message: 'Ошибка: ${result.error}',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingSubscriptions[subscription.id] = false);
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _updateAllSubscriptions() async {
    setState(() => _isUpdating = true);

    try {
      final results = await SubscriptionService.updateAllSubscriptions();

      if (mounted) {
        setState(() => _isUpdating = false);

        final successCount = results.where((r) => r.success).length;
        final totalServers = results.fold<int>(0, (sum, r) => sum + r.serverCount);

        CustomNotification.show(
          context,
          message: 'Обновлено $successCount подписок, добавлено $totalServers серверов',
          type: NotificationType.success,
        );

        _loadSubscriptions();
        widget.onServersUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteSubscription(Subscription subscription) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeManager().settings.accentColor,
        title: const Text('Удалить подписку?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Название: ${subscription.name}'),
            const SizedBox(height: 8),
            Text('Серверов: ${subscription.serverCount}'),
            const SizedBox(height: 16),
            const Text(
              'Серверы из этой подписки также будут удалены.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await SubscriptionService.removeSubscriptionServers(subscription);
        await SubscriptionService.deleteSubscription(subscription.id);

        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Подписка удалена',
            type: NotificationType.success,
          );
          _loadSubscriptions();
          widget.onServersUpdated();
        }
      } catch (e) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Ошибка: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _toggleAutoUpdate(Subscription subscription, bool value) async {
    try {
      final updated = subscription.copyWith(autoUpdate: value);
      await SubscriptionService.updateSubscription(updated);
      _loadSubscriptions();
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Заголовок с кнопками
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Подписки',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: themeManager.settings.primaryColor,
                ),
              ),
              const Spacer(),
              // Кнопка обновить все
              IconButton(
                icon: _isUpdating
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.refresh),
                tooltip: 'Обновить все подписки',
                onPressed: _isUpdating ? null : _updateAllSubscriptions,
              ),
              // Кнопка добавить
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Добавить подписку',
                onPressed: _showAddDialog,
              ),
            ],
          ),
        ),

        // Список подписок
        if (_subscriptions.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.rss_feed,
                    size: 64,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет подписок',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите + чтобы добавить',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _subscriptions.length,
              itemBuilder: (context, index) {
                final subscription = _subscriptions[index];
                final isUpdating = _updatingSubscriptions[subscription.id] ?? false;

                return Card(
                  color: themeManager.settings.accentColor.withOpacity(0.3),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Заголовок с кнопками
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subscription.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Серверов: ${subscription.serverCount}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Кнопка обновить
                            IconButton(
                              icon: isUpdating
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(Icons.refresh, size: 20),
                              onPressed: isUpdating
                                  ? null
                                  : () => _updateSubscription(subscription),
                              tooltip: 'Обновить',
                            ),
                            // Кнопка удалить
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () => _deleteSubscription(subscription),
                              tooltip: 'Удалить',
                              color: Colors.red.withOpacity(0.7),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // URL
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            subscription.url,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Информация и переключатель автообновления
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Обновлено: ${_formatDate(subscription.lastUpdated)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Автообновление',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            Switch(
                              value: subscription.autoUpdate,
                              onChanged: (value) =>
                                  _toggleAutoUpdate(subscription, value),
                              activeColor: themeManager.settings.primaryColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    if (diff.inDays == 1) return 'вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';

    return '${date.day}.${date.month}.${date.year}';
  }
}

class SettingsView extends StatefulWidget {
  final VoidCallback? onThemeChanged;
  final VoidCallback? onSettingsChanged;

  const SettingsView({super.key, this.onThemeChanged, this.onSettingsChanged});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late Future<AppSettings> _settingsFuture;
  final _portCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsFuture = SettingsStorage.loadSettings().then((s) {
      if (mounted) {
        _portCtrl.text = s.localPort.toString();
      }
      return s;
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePort() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: int.tryParse(_portCtrl.text) ?? 2080,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: currentSettings.pingType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    widget.onSettingsChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: 'Локальный порт сохранен. Переподключитесь для применения.',
        type: NotificationType.success,
      );
    }
  }

  Widget _buildMenuCard(
      String title,
      String subtitle,
      IconData icon,
      VoidCallback onTap,
      ) {
    final themeManager = ThemeManager();
    return Card(
      color: themeManager.settings.accentColor.withOpacity(0.3),
      child: ListTile(
        leading: Icon(icon, color: themeManager.settings.primaryColor, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Icon(Icons.arrow_forward_ios, color: themeManager.settings.secondaryColor),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // === ЛОКАЛЬНЫЙ ПОРТ ===
            Text(
              "Основные настройки",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            Card(
              color: themeManager.settings.accentColor.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Локальный порт",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "Например: 2080",
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _savePort,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeManager.settings.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          ),
                          child: const Text(
                            "Сохранить",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // === ПОДМЕНЮ ===
            Text(
              "Дополнительные настройки",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            _buildMenuCard(
              "Поведение приложения",
              "Автозапуск, свертывание в трей и другое",
              Icons.settings_applications,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BehaviorSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              "Маршрутизация",
              "Правила для доменов, IP-адресов и блокировки",
              Icons.route,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RoutingSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              "Настройки пинга",
              "Выбор типа пинга (TCP или через прокси)",
              Icons.speed,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PingSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),

            const SizedBox(height: 32),

            // === ВНЕШНИЙ ВИД ===
            Text(
              "Внешний вид",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            AnimatedBuilder(
              animation: themeManager,
              builder: (context, child) {
                return Card(
                  color: themeManager.settings.accentColor.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (themeManager.hasCustomBackground) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Image.file(
                                  File(themeManager.settings.backgroundImagePath!),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    onPressed: () async {
                                      await themeManager.removeBackground();
                                      widget.onThemeChanged?.call();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text("Прозрачность фона", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          Slider(
                            value: themeManager.settings.backgroundOpacity,
                            min: 0.1,
                            max: 0.9,
                            divisions: 8,
                            label: '${(themeManager.settings.backgroundOpacity * 100).round()}%',
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              themeManager.updateOpacity(value);
                            },
                            onChangeEnd: (value) {
                              themeManager.saveTheme();
                            },
                          ),

                          const SizedBox(height: 8),
                          Text("Размытие фона", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          Slider(
                            value: themeManager.settings.blurIntensity,
                            min: 0,
                            max: 30,
                            divisions: 30,
                            label: themeManager.settings.blurIntensity.round().toString(),
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              themeManager.updateBlur(value);
                            },
                            onChangeEnd: (value) {
                              themeManager.saveTheme();
                            },
                          ),

                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await themeManager.pickBackgroundImage();
                              widget.onThemeChanged?.call();
                            },
                            icon: const Icon(Icons.image),
                            label: Text(themeManager.hasCustomBackground
                                ? "Изменить фон"
                                : "Выбрать фоновое изображение"
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: themeManager.settings.primaryColor,
                              side: BorderSide(color: themeManager.settings.primaryColor),
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        Text(
                          "Цвета интерфейса автоматически адаптируются под выбранное изображение",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
class BehaviorSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const BehaviorSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  bool _autoStart = false;
  bool _minimizeToTray = true;
  bool _startMinimized = false;
  bool _autoConnectLastServer = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _autoStart = settings.autoStart;
        _minimizeToTray = settings.minimizeToTray;
        _startMinimized = settings.startMinimized;
        _autoConnectLastServer = settings.autoConnectLastServer;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveBehaviorSettings() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: currentSettings.pingType,
      autoStart: _autoStart,
      minimizeToTray: _minimizeToTray,
      startMinimized: _startMinimized,
      autoConnectLastServer: _autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);
    await AutoStartService.toggle(_autoStart);

    if (mounted) {
      widget.onSettingsChanged?.call();
    }
  }

  Widget _buildSwitch(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Card(
      color: ThemeManager().settings.accentColor.withOpacity(0.3),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        value: value,
        activeColor: ThemeManager().settings.primaryColor,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      body: Stack(
        children: [
          // Кастомный фон
          if (themeManager.hasCustomBackground)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(themeManager.settings.backgroundImagePath!),
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: themeManager.settings.blurIntensity,
                      sigmaY: themeManager.settings.blurIntensity,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(
                          1.0 - themeManager.settings.backgroundOpacity
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Контент
          Column(
            children: [
              AppBar(
                backgroundColor: themeManager.settings.accentColor.withOpacity(0.9),
                title: const Text('Поведение приложения'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildSwitch(
                      "Автозапуск при старте",
                      "Приложение будет запускаться вместе с системой",
                      _autoStart,
                          (value) {
                        setState(() => _autoStart = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Сворачивать в трей",
                      "Приложение будет сворачиваться в трей",
                      _minimizeToTray,
                          (value) {
                        setState(() => _minimizeToTray = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Запускать свёрнутым",
                      "Приложение будет сразу сворачиваться в трей при автозапуске",
                      _startMinimized,
                          (value) {
                        setState(() => _startMinimized = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Автоподключение к последнему серверу",
                      "Автоматически подключаться к последнему использованному серверу при запуске",
                      _autoConnectLastServer,
                          (value) {
                        setState(() => _autoConnectLastServer = value);
                        _saveBehaviorSettings();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// === СТРАНИЦА: НАСТРОЙКИ МАРШРУТИЗАЦИИ ===

class RoutingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const RoutingSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<RoutingSettingsPage> createState() => _RoutingSettingsPageState();
}

class _RoutingSettingsPageState extends State<RoutingSettingsPage> {
  final _directDomainsCtrl = TextEditingController();
  final _blockDomainsCtrl = TextEditingController();
  final _directIpsCtrl = TextEditingController();
  final _proxyDomainsCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _directDomainsCtrl.dispose();
    _blockDomainsCtrl.dispose();
    _directIpsCtrl.dispose();
    _proxyDomainsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _directDomainsCtrl.text = settings.directDomains;
        _blockDomainsCtrl.text = settings.blockedDomains;
        _directIpsCtrl.text = settings.directIps;
        _proxyDomainsCtrl.text = settings.proxyDomains;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRoutingSettings() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: _directDomainsCtrl.text,
      blockedDomains: _blockDomainsCtrl.text,
      directIps: _directIpsCtrl.text,
      proxyDomains: _proxyDomainsCtrl.text,
      pingType: currentSettings.pingType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    if (mounted) {
      widget.onSettingsChanged?.call();

      CustomNotification.show(
        context,
        message: 'Настройки маршрутизации сохранены. Переподключитесь для применения.',
        type: NotificationType.success,
      );
    }
  }

  Widget _buildField(String label, String hint, TextEditingController ctrl, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      body: Stack(
        children: [
          // Кастомный фон
          if (themeManager.hasCustomBackground)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(themeManager.settings.backgroundImagePath!),
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: themeManager.settings.blurIntensity,
                      sigmaY: themeManager.settings.blurIntensity,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(
                          1.0 - themeManager.settings.backgroundOpacity
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Контент
          Column(
            children: [
              AppBar(
                backgroundColor: themeManager.settings.accentColor.withOpacity(0.9),
                title: const Text('Настройки маршрутизации'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      "Можно вводить через запятую, пробел или с новой строки.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Сайты напрямую (Direct)",
                      "yandex.ru, vk.com, ru...",
                      _directDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Принудительно через VPN",
                      "google.com, youtube.com...",
                      _proxyDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Блокировка сайтов (Block)",
                      "ads.google.com, tracker.com...",
                      _blockDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "IP напрямую (CIDR)",
                      "192.168.0.0/16, 10.0.0.0/8...",
                      _directIpsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveRoutingSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeManager.settings.primaryColor,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save, size: 24),
                            SizedBox(width: 12),
                            Text("Сохранить настройки"),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// === СТРАНИЦА: НАСТРОЙКИ ПИНГА ===

class PingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const PingSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<PingSettingsPage> createState() => _PingSettingsPageState();
}

class _PingSettingsPageState extends State<PingSettingsPage> {
  String _pingType = 'tcp';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _pingType = settings.pingType;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePingSettings(String newType) async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: newType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    if (mounted) {
      widget.onSettingsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      body: Stack(
        children: [
          // Кастомный фон
          if (themeManager.hasCustomBackground)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(themeManager.settings.backgroundImagePath!),
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: themeManager.settings.blurIntensity,
                      sigmaY: themeManager.settings.blurIntensity,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(
                          1.0 - themeManager.settings.backgroundOpacity
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Контент
          Column(
            children: [
              AppBar(
                backgroundColor: themeManager.settings.accentColor.withOpacity(
                    0.9),
                title: const Text('Настройки пинга'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      "Тип пинга",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: themeManager.settings.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: themeManager.settings.accentColor.withOpacity(0.3),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Text('TCP пинг'),
                            subtitle: const Text(
                              'Прямое подключение к серверу',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            value: 'tcp',
                            groupValue: _pingType,
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              setState(() => _pingType = value!);
                              _savePingSettings(value!);
                            },
                          ),
                          const Divider(height: 1),
                          RadioListTile<String>(
                            title: const Text('Пинг Прокси'),
                            subtitle: const Text(
                              'Проверка через локальный прокси',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            value: 'proxy',
                            groupValue: _pingType,
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              setState(() => _pingType = value!);
                              _savePingSettings(value!);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue,
                                  size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Подсказка',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '• TCP пинг - для проверки удалённости от серверов\n'
                                '• Пинг через прокси - используйте для проверки доступности сервера',
                            style: TextStyle(fontSize: 13, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}