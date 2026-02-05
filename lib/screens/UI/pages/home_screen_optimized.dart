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

import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'package:keqdis/screens/ping_manager.dart';

import '../widgets/add_server_dialog.dart';
import '../widgets/custom_notification.dart';

import 'home_sidebar.dart';
import 'home_main_content.dart';

class HomeScreen extends StatefulWidget {
  final bool isAutoStarted;

  const HomeScreen({super.key, required this.isAutoStarted});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WindowListener {
  final _trayService = TrayService();
  late final AppLifecycleListener _listener;

  late VpnController _vpnController;
  late PingManager _pingManager;
  final ThemeManager _themeManager = ThemeManager();

  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  final Map<String, bool> _serverPingingState = {};

  AppSettings _settings = AppSettings();
  bool _tunAvailable = false;
  bool _isReallyExiting = false;

  Timer? _autoUpdateTimer;

  // Image cache
  ImageProvider? _cachedBackgroundImageProvider;
  String? _currentBackgroundImagePath;

  @override
  void initState() {
    super.initState();

    _vpnController = VpnController();
    _pingManager = PingManager();
    _themeManager.addListener(_onThemeChanged);

    windowManager.addListener(this);
    _listener = AppLifecycleListener(onExitRequested: _onAppExit);
    windowManager.setPreventClose(true);

    _initializeApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCachedImage();
  }

  Future<void> _initializeApp() async {
    try {
      await Future.wait([
        _vpnController.loadInitialServers(),
        _loadSettings(),
      ]);

      if (!mounted) return;

      await _checkTunAvailability();
      await _initializeTray();

      _vpnController.addListener(_updateTrayStatus);

      _startSubscriptionAutoUpdate();

      if (_settings.autoConnectLastServer) {
        await _vpnController.autoConnectToLastServer();
      }
    } catch (e) {
      debugPrint('Ошибка инициализации: $e');
    }
  }

  void _updateTrayStatus() {
    _trayService.updateConnectionStatus(_vpnController.isConnected);
  }

  Future<void> _loadSettings() async {
    _settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {});
    }
  }

  void _onThemeChanged() {
    if (mounted) {
      _updateCachedImage();
    }
  }

  void _updateCachedImage() {
    final newPath = _themeManager.settings.backgroundImagePath;
    if (_currentBackgroundImagePath == newPath && _cachedBackgroundImageProvider != null) {
      return;
    }
    _currentBackgroundImagePath = newPath;

    if (newPath == null) {
      if (_cachedBackgroundImageProvider != null) {
        setState(() => _cachedBackgroundImageProvider = null);
      }
      return;
    }

    final imageProvider = FileImage(File(newPath));
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio).round();
    final screenHeight = (mediaQuery.size.height * mediaQuery.devicePixelRatio).round();

    setState(() {
      _cachedBackgroundImageProvider = ResizeImage(
        imageProvider,
        width: screenWidth,
        height: screenHeight,
      );
    });
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
    _vpnController.removeListener(_updateTrayStatus);
    windowManager.removeListener(this);
    _listener.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    _autoUpdateTimer?.cancel();
    _vpnController.dispose();
    _pingManager.dispose();
    _themeManager.removeListener(_onThemeChanged);
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

        CustomNotification.show(
          context,
          message: 'Режим изменен на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
          type: NotificationType.success,
        );
      } catch (e) {
        CustomNotification.show(
          context,
          message: 'Ошибка смены режима: $e',
          type: NotificationType.error,
        );
      }
    } else {
      _vpnController.switchVpnMode(newMode);
      CustomNotification.show(
        context,
        message: 'Режим изменен на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
        type: NotificationType.success,
      );
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
        final exePath = Platform.resolvedExecutable;

        await Process.start(
          'powershell',
          [
            '-Command',
            'Start-Process',
            '-FilePath',
            '\"$exePath\"',
            '-Verb',
            'RunAs',
          ],
          runInShell: true,
          mode: ProcessStartMode.detached,
        );

        await Future.delayed(const Duration(milliseconds: 500));

        await _exitApp();
      } else {
        CustomNotification.show(
          context,
          message: 'Перезапуск с правами администратора доступен только на Windows',
          type: NotificationType.error,
        );
      }
    } catch (e) {
      CustomNotification.show(
        context,
        message: 'Ошибка перезапуска: $e',
        type: NotificationType.error,
      );
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

          CustomNotification.show(
            context,
            message: 'Добавлено серверов: $successCount из ${configs.length}',
            type: NotificationType.success,
          );
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
        ChangeNotifierProvider.value(value: _themeManager),
      ],
      child: Scaffold(
        body: Stack(
          children: [
            if (_themeManager.hasCustomBackground && _cachedBackgroundImageProvider != null)
              Positioned.fill(
                child: _buildOptimizedBackground(context),
              ),
            Row(
              children: [
                HomeSidebar(
                  currentTab: _currentTab,
                  onTabChanged: (tab) => setState(() => _currentTab = tab),
                ),
                Container(
                  width: 1,
                  color: Colors.white.withAlpha(26), // 0.1 opacity
                ),
                Expanded(
                  child: HomeMainContent(
                    currentTab: _currentTab,
                    settings: _settings,
                    tunAvailable: _tunAvailable,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: () {
                      _searchController.clear();
                      _vpnController.searchServers('');
                    },
                    onAddServer: _showAddServerDialog,
                    onPingAll: _pingAllServers,
                    onPing: _pingServer,
                    serverPingingState: _serverPingingState,
                    onVpnModeChanged: _handleVpnModeSwitch,
                    onSettingsChanged: _loadSettings,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizedBackground(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _cachedBackgroundImageProvider!,
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
}
