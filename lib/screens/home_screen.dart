import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../core_manager.dart';
import '../unified_storage.dart';
import '../improved_settings_storage.dart';
import '../system_proxy.dart';
import '../config_validator.dart';
import '../tray_service.dart';
import '../autostart_service.dart';
import '../improved_theme_manager.dart';
import '../ping_service.dart';
import '../improved_subscription_service.dart';
import '../custom_notification.dart';
import '../single_instance_manager.dart';
import '../tun_service.dart';
import 'package:country_flags/country_flags.dart';
import 'subscriptions_screen.dart';
import 'settings_screen.dart';

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

  // ========== VPN РЕЖИМ (TUN/SYSTEM PROXY) ==========
  VpnMode _vpnMode = VpnMode.systemProxy;
  bool _tunAvailable = false;

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
    _listener = AppLifecycleListener(onExitRequested: _onAppExit);
    windowManager.setPreventClose(true);

    // ИСПРАВЛЕНО: Вызываем автоподключение ПОСЛЕ загрузки данных
    _initializeApp();

    // НОВОЕ: Очистка кэша пингов каждые 5 минут
    _pingCacheCleanup = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _cleanupOldPingResults(),
    );
  }

  // НОВАЯ ФУНКЦИЯ: Правильная последовательность инициализации
  Future<void> _initializeApp() async {
    try {
      // Шаг 1: Загружаем данные и настройки
      await _loadData();

      // Шаг 1.5: Проверяем доступность TUN
      await _checkTunAvailability();

      // Шаг 2: Инициализируем трей
      await _initializeTray();

      // Шаг 3: Запускаем автообновление подписок
      _startSubscriptionAutoUpdate();

      // Шаг 4: Обновляем подписки при старте (опционально)
      _updateSubscriptionsOnStart();

      // Шаг 5: ВАЖНО - автоподключение только после загрузки данных
      await _autoConnectToLastServer();
    } catch (e) {
      print('❌ Ошибка инициализации: $e');
    }
  }

  // ========== ПРОВЕРКА TUN ДОСТУПНОСТИ ==========
  Future<void> _checkTunAvailability() async {
    final available = await TunService.isTunAvailable();
    if (mounted) {
      setState(() => _tunAvailable = available);
      print('🔍 TUN доступен: $_tunAvailable');
    }
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
      // Если настройки еще не загружены (на всякий случай) или функция выключена
      if (!_settings.autoConnectLastServer) return;

      // Если серверы пустые, нет смысла искать (защита)
      if (_servers.isEmpty) return;

      final lastServer = await UnifiedStorage.getLastServer();
      if (lastServer == null) return;

      // Теперь поиск точно сработает, если сервер есть в списке
      final index = _servers.indexWhere((s) => s.id == lastServer.id);
      if (index == -1) return;

      if (mounted) {
        setState(() => _selectedServerIndex = index);
        // Можно сразу вызывать подключение
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
          mode: _vpnMode, // ← ДОБАВЛЕНО: передаем выбранный режим
        );

        await UnifiedStorage.saveLastServer(selectedServer.id);

        if (mounted) setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = "Подключено (${_vpnMode == VpnMode.tun ? 'TUN' : 'Proxy'})";
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

          // VPN РЕЖИМ ПЕРЕКЛЮЧАТЕЛЬ (TUN / SYSTEM PROXY)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Режим работы',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 12),

                // Двойной переключатель
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // System Proxy
                      Expanded(
                        child: _buildModeButton(
                          icon: Icons.public,
                          label: 'Proxy',
                          isSelected: _vpnMode == VpnMode.systemProxy,
                          isEnabled: !_isConnecting,
                          onTap: () => _handleVpnModeChange(VpnMode.systemProxy),
                        ),
                      ),

                      // TUN
                      Expanded(
                        child: _buildModeButton(
                          icon: Icons.vpn_lock,
                          label: 'TUN',
                          isSelected: _vpnMode == VpnMode.tun,
                          isEnabled: !_isConnecting,
                          onTap: () => _handleVpnModeChange(VpnMode.tun),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Описание режима
                Text(
                  _vpnMode == VpnMode.systemProxy
                      ? 'Порт: ${_settings.localPort}'
                      : 'Глобальный режим (TUN)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ========== КНОПКА РЕЖИМА VPN ==========
  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isEnabled,
    required VoidCallback onTap,
    bool requiresAdmin = false,
  }) {
    final themeManager = ThemeManager();

    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 60, // Фиксированная минимальная высота
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? themeManager.settings.primaryColor.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? themeManager.settings.primaryColor
                    : (isEnabled ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.3)),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? themeManager.settings.primaryColor
                      : (isEnabled ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.3)),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (requiresAdmin)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.admin_panel_settings,
                    size: 12,
                    color: Colors.orange.withOpacity(0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ========== ОБРАБОТЧИК СМЕНЫ РЕЖИМА ==========
  Future<void> _handleVpnModeChange(VpnMode newMode) async {
    // Если TUN режим — проверяем права администратора в реалтайм
    if (newMode == VpnMode.tun) {
      final hasAdmin = await TunService.hasAdminRights();
      if (!hasAdmin) {
        _showAdminRequiredDialog();
        return;
      }
    }

    // Если подключены - переключаем на лету
    if (_isConnected && _selectedServerIndex != -1) {
      try {
        setState(() {
          _isConnecting = true;
          _status = "Переключение режима...";
        });

        final config = _servers[_selectedServerIndex].config;
        await _coreManager.switchMode(config, newMode);

        setState(() {
          _vpnMode = newMode;
          _isConnecting = false;
          _status = "Подключено";
        });

        CustomNotification.show(
          context,
          message: 'Режим изменен: ${newMode == VpnMode.tun ? "TUN" : "System Proxy"}',
          type: NotificationType.success,
        );
      } catch (e) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _status = "Ошибка: ${e.toString()}";
        });

        CustomNotification.show(
          context,
          message: 'Ошибка переключения: $e',
          type: NotificationType.error,
        );
      }
    } else {
      // Просто меняем режим для следующего подключения
      setState(() => _vpnMode = newMode);

      CustomNotification.show(
        context,
        message: 'Режим будет применен при подключении',
        type: NotificationType.info,
      );
    }
  }

  void _showAdminRequiredDialog() {
    // Сохраняем контекст _MainShellState ПЕРЕД диалогом.
    // После Navigator.pop() контекст диалога мёртв — его нельзя использовать.
    final parentContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ThemeManager().settings.accentColor,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Требуются права администратора')),
          ],
        ),
        content: const Text(
          'TUN режим требует прав администратора для создания виртуального сетевого адаптера (wintun).\n\n'
              'Нажимайте «Перезапустить» — появится окно UAC Windows. '
              'Подтвердите запуск от имени администратора.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);

              final success = await TunService.requestAdminRights();

              if (!mounted) return;

              if (success) {
                // exit(0) идёт ПЕРЕД уведомлением: уведомление всё равно не покажется
                // после убийства процесса, но exit(0) гарантированно выполнится.
                // Раньше порядок был обратным — show() кидала на мёртвом context и
                // exit(0) никогда не достигался.
                exit(0);
              } else {
                CustomNotification.show(
                  parentContext,
                  message: 'Не удалось перезапустить с правами администратора',
                  type: NotificationType.error,
                );
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Перезапустить'),
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

  Widget _buildSubscriptionsView() {
    return SubscriptionsView(
      onServersUpdated: _loadData,
    );
  }

  Widget _buildSettingsView() {
    return SettingsView(
      onThemeChanged: () {
        setState(() {});
      },
      onSettingsChanged: _loadData,
    );
  }
}