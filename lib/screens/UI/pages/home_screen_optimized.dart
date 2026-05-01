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
import 'package:keqdis/localization/app_localization.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'package:keqdis/screens/ping_manager.dart';

import '../widgets/add_server_dialog.dart';
import '../widgets/custom_notification.dart';

import 'home_top_bar.dart';
import 'home_main_content.dart';

class HomeScreen extends StatefulWidget {
  final bool isAutoStarted;
  final bool startMinimized;

  const HomeScreen({
    super.key,
    required this.isAutoStarted,
    this.startMinimized = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WindowListener {
  static const Duration _subscriptionAutoUpdateInterval = Duration(hours: 12);
  static const Duration _subscriptionAutoUpdateCheckPeriod = Duration(
    minutes: 15,
  );

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
  bool _isInitialized = false;
  bool _isWindowActive = true;

  Timer? _autoUpdateTimer;
  bool _isAutoUpdateRunning = false;

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
      // Сначала загружаем настройки и серверы
      await Future.wait([
        _vpnController.loadInitialServers(),
        _loadSettings(),
        SettingsStorage.loadCollapsedServerGroups(),
      ]);

      if (!mounted) return;

      await _checkTunAvailability();
      await _initializeTray();
      await _applyLaunchMinimizedIfNeeded();

      _vpnController.addListener(_updateTrayStatus);
      _startSubscriptionAutoUpdate();

      // Автоподключение должно работать при автозапуске и при старте в свернутом режиме.
      final shouldAutoConnectOnLaunch =
          widget.isAutoStarted || widget.startMinimized;
      if (shouldAutoConnectOnLaunch && _settings.autoConnectLastServer) {
        // Если сохранён TUN, но приложение запущено без админ-прав, падаем на systemProxy.
        if (_vpnController.vpnMode == VpnMode.tun &&
            !await TunService.hasAdminRights()) {
          debugPrint(
            'Auto-connect: no admin rights for TUN, falling back to systemProxy',
          );
          _vpnController.setVpnModeForSession(VpnMode.systemProxy);
        }
        debugPrint('Auto-connecting to last server (autostart only)...');
        await _vpnController.autoConnectToLastServer();
      }

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Ошибка инициализации: $e');
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    }
  }

  void _updateTrayStatus() {
    _trayService.updateConnectionStatus(_vpnController.isConnected);
  }

  Future<void> _loadSettings() async {
    _settings = await SettingsStorage.loadSettings();
    if (mounted) setState(() {});
  }

  void _onThemeChanged() {
    if (mounted) _updateCachedImage();
  }

  void _updateCachedImage() {
    final newPath = _themeManager.settings.backgroundImagePath;
    if (_currentBackgroundImagePath == newPath &&
        _cachedBackgroundImageProvider != null)
      return;
    _currentBackgroundImagePath = newPath;

    if (newPath == null) {
      if (_cachedBackgroundImageProvider != null) {
        setState(() => _cachedBackgroundImageProvider = null);
      }
      return;
    }

    final imageProvider = FileImage(File(newPath));
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio)
        .round();
    final screenHeight = (mediaQuery.size.height * mediaQuery.devicePixelRatio)
        .round();

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
    if (mounted) setState(() => _tunAvailable = available);
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

  Future<void> _applyLaunchMinimizedIfNeeded() async {
    final shouldHideOnLaunch = widget.isAutoStarted || widget.startMinimized;
    if (!shouldHideOnLaunch) return;

    // Windows can restore/show a window once during startup sequence.
    // Re-apply hide with a short delay to reliably keep app in tray.
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
    await Future.delayed(const Duration(milliseconds: 250));
    await windowManager.hide();
  }

  void _startSubscriptionAutoUpdate() {
    _autoUpdateTimer?.cancel();
    unawaited(_runSubscriptionAutoUpdateCheck());
    _autoUpdateTimer = Timer.periodic(_subscriptionAutoUpdateCheckPeriod, (_) {
      unawaited(_runSubscriptionAutoUpdateCheck());
    });
  }

  Future<void> _runSubscriptionAutoUpdateCheck() async {
    if (_isAutoUpdateRunning || !mounted) return;
    _isAutoUpdateRunning = true;
    try {
      final results = await SubscriptionService.updateDueSubscriptions(
        interval: _subscriptionAutoUpdateInterval,
      );
      if (!mounted) return;
      if (results.any((r) => r.success)) {
        await _vpnController.loadInitialServers();
      }
    } catch (e) {
      debugPrint('Ошибка автообновления: $e');
    } finally {
      _isAutoUpdateRunning = false;
    }
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
  void onWindowBlur() {
    if (mounted) setState(() => _isWindowActive = false);
  }

  @override
  void onWindowFocus() {
    if (mounted) setState(() => _isWindowActive = true);
  }

  @override
  void onWindowMinimize() {
    if (mounted) setState(() => _isWindowActive = false);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _isWindowActive = true);
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
    final s = _themeManager.settings;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: s.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: s.borderColor),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('exit'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: s.textColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('confirm_exit'),
                style: TextStyle(color: s.secondaryTextColor),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: s.secondaryTextColor,
                        side: BorderSide(color: s.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(context.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _exitApp();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: s.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(context.tr('exit')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          message:
              'Режим изменён на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
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
        message:
            'Режим изменён на ${newMode == VpnMode.tun ? 'TUN' : 'System Proxy'}',
        type: NotificationType.success,
      );
    }
  }

  void _showAdminRequiredDialog() {
    final s = _themeManager.settings;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: s.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: s.borderColor),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: s.primaryColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('admin_required'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: s.textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('tun_requires_admin'),
                style: TextStyle(color: s.secondaryTextColor),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: s.secondaryTextColor,
                        side: BorderSide(color: s.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(context.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _restartAsAdmin();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(context.tr('restart')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: s.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restartAsAdmin() async {
    try {
      if (Platform.isWindows) {
        final success = await TunService.requestAdminRights();
        if (!success && mounted) {
          CustomNotification.show(
            context,
            message: 'Не удалось перезапустить',
            type: NotificationType.error,
          );
        }
      } else {
        CustomNotification.show(
          context,
          message: 'Доступно только на Windows',
          type: NotificationType.error,
        );
      }
    } catch (e) {
      CustomNotification.show(
        context,
        message: 'Ошибка: $e',
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
      if (mounted) setState(() => _serverPingingState[server.id] = false);
    }
  }

  Future<void> _pingAllServers(List<ServerItem> servers) async {
    await _pingManager.pingMultipleServers(
      servers,
      _settings.pingType,
      (server, isComplete) {},
    );
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
              debugPrint('Ошибка добавления: $e');
            }
          }
          CustomNotification.show(
            context,
            message: 'Добавлено: $successCount из ${configs.length}',
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
      child: _isInitialized ? _buildMainContent() : _buildLoadingScreen(),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: _themeManager.settings.backgroundColor,
      body: Center(
        child: CircularProgressIndicator(
          color: _themeManager.settings.primaryColor,
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final s = _themeManager.settings;
    final desktopLayout = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      backgroundColor: s.backgroundColor,
      body: Stack(
        children: [
          // ── Фоновое изображение (на весь экран) ───────────────────────
          if (_themeManager.hasCustomBackground &&
              _cachedBackgroundImageProvider != null)
            Positioned.fill(child: _buildOptimizedBackground()),

          // ── Основной контент: desktop shell / compact shell ────────────
          if (desktopLayout)
            Row(
              children: [
                _DesktopSidebar(
                  currentTab: _currentTab,
                  onTabChanged: (tab) => setState(() => _currentTab = tab),
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
                    enableWaveAnimation: _isWindowActive,
                    isDesktopLayout: true,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                HomeTopBar(
                  currentTab: _currentTab,
                  onTabChanged: (tab) => setState(() => _currentTab = tab),
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
                    enableWaveAnimation: _isWindowActive,
                    isDesktopLayout: false,
                  ),
                ),
              ],
            ),

          // ── Версия: плавающая карточка снизу по центру ─────────────────
          const Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: _VersionBadge(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _cachedBackgroundImageProvider!,
          fit: BoxFit.cover, // ← заполняет весь экран включая где была панель
          errorBuilder: (context, error, _) {
            debugPrint('Ошибка загрузки фона: $error');
            Future.microtask(() => _themeManager.removeBackground());
            return Container(color: _themeManager.settings.backgroundColor);
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

class _DesktopSidebar extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;

  const _DesktopSidebar({required this.currentTab, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    final items = <({int index, IconData icon, String label})>[
      (index: 0, icon: Icons.dns_rounded, label: context.tr('servers')),
      (
        index: 1,
        icon: Icons.language_rounded,
        label: context.tr('subscriptions'),
      ),
      (index: 2, icon: Icons.settings_rounded, label: context.tr('settings')),
    ];

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: s.cardColor.withOpacity(0.92),
        border: Border(right: BorderSide(color: s.borderColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KEQDIS',
                style: TextStyle(
                  color: s.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),
              for (final item in items) ...[
                _DesktopNavTile(
                  icon: item.icon,
                  label: item.label,
                  active: currentTab == item.index,
                  onTap: () => onTabChanged(item.index),
                ),
                const SizedBox(height: 8),
              ],
              const Spacer(),
              Consumer<VpnController>(
                builder: (_, ctrl, __) {
                  final status = ctrl.isConnecting
                      ? context.tr('connecting')
                      : ctrl.isConnected
                      ? context.tr('connected')
                      : context.tr('disconnected');
                  final statusColor = ctrl.isConnecting
                      ? Colors.orange
                      : ctrl.isConnected
                      ? Colors.green
                      : s.secondaryTextColor;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: s.searchBarColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: s.borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
                              color: s.textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DesktopNavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? s.primaryColor.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? s.primaryColor.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? s.primaryColor : s.secondaryTextColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? s.textColor : s.secondaryTextColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionBadge extends StatefulWidget {
  const _VersionBadge();

  @override
  State<_VersionBadge> createState() => _VersionBadgeState();
}

class _VersionBadgeState extends State<_VersionBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    final scheme = Theme.of(context).colorScheme;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: s.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: s.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'v0.0.3',
              style: TextStyle(
                color: scheme.onSurfaceVariant.withOpacity(0.85),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
