import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keqdis/core/core_manager.dart';
import 'package:keqdis/core/tun_service.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';

class VpnController extends ChangeNotifier {
  final CoreManager _coreManager = CoreManager();

  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = "Отключено";
  VpnMode _vpnMode = VpnMode.systemProxy;

  List<ServerItem> _allServers = [];
  ServerItem? _selectedServer;
  List<ServerItem> _favoriteServers = [];
  List<ServerItem> _searchResults = [];

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get status => _status;
  VpnMode get vpnMode => _vpnMode;

  /// Use only for one session (no persistence). Useful for autostart fallback.
  void setVpnModeForSession(VpnMode mode) {
    if (_vpnMode == mode) return;
    debugPrint('VpnController: Setting VPN mode for session: ${mode.name}');
    _vpnMode = mode;
    notifyListeners();
  }

  List<ServerItem> get allServers => _allServers;
  ServerItem? get selectedServer => _selectedServer;
  List<ServerItem> get favoriteServers => _favoriteServers;
  List<ServerItem> get searchResults => _searchResults;

  VpnController() {
    _coreManager.addListener(_onCoreStatusChanged);
    _loadInitialSettings();
  }

  void _onCoreStatusChanged() {
    if (!_coreManager.isRunning && isConnected) {
      // Core was stopped externally
      _isConnected = false;
      _isConnecting = false;
      _status = "Отключено";
      notifyListeners();
    }
  }

  Future<void> _loadInitialSettings() async {
    final settings = await SettingsStorage.loadSettings();
    _vpnMode = VpnMode.values.firstWhere(
          (e) => e.name == settings.lastVpnMode,
      orElse: () => VpnMode.systemProxy,
    );
    debugPrint('VpnController: Loaded VPN mode: ${_vpnMode.name}');
    notifyListeners();
  }

  Future<void> loadInitialServers() async {
    _allServers = await UnifiedStorage.getServers();
    _sortServers();
    _favoriteServers = _allServers.where((s) => s.isFavorite).toList();
    final lastServerId = await UnifiedStorage.loadLastServerId();
    if (lastServerId != null) {
      final potentialServers = _allServers.where((s) => s.id == lastServerId);
      _selectedServer = potentialServers.isNotEmpty ? potentialServers.first : null;
    }
    _searchResults = [];
    debugPrint('VpnController: Loaded ${_allServers.length} servers');
    notifyListeners();
  }

  void _sortServers() {
    _allServers.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;

      return a.displayName.compareTo(b.displayName);
    });
  }

  Future<void> searchServers(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _searchResults = _allServers
        .where((s) => s.displayName.toLowerCase().contains(query.toLowerCase()))
        .toList();

    _searchResults.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    debugPrint('VpnController: Search found ${_searchResults.length} servers for "$query"');
    notifyListeners();
  }

  void selectServer(ServerItem server) {
    if (_isConnecting || _isConnected) {
      debugPrint('VpnController: Cannot select server while connecting or connected');
      return;
    }

    _selectedServer = server;
    debugPrint('VpnController: Selected server: ${server.displayName}');
    notifyListeners();
  }

  Future<void> switchVpnMode(VpnMode newMode) async {
    if (_vpnMode == newMode) return;

    debugPrint('VpnController: Switching VPN mode from ${_vpnMode.name} to ${newMode.name}');
    _vpnMode = newMode;

    final settings = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(AppSettings(
      localPort: settings.localPort,
      directDomains: settings.directDomains,
      blockedDomains: settings.blockedDomains,
      directIps: settings.directIps,
      proxyDomains: settings.proxyDomains,
      autoStart: settings.autoStart,
      minimizeToTray: settings.minimizeToTray,
      startMinimized: settings.startMinimized,
      pingType: settings.pingType,
      autoConnectLastServer: settings.autoConnectLastServer,
      lastVpnMode: newMode.name,
    ));

    notifyListeners();

    if (_isConnected) {
      debugPrint('VpnController: Reconnecting with new VPN mode...');
      await disconnect();
      await connect();
    }
  }

  Future<bool> toggleConnection() async {
    if (_isConnecting) {
      debugPrint('VpnController: Toggle ignored - connection in progress');
      return false;
    }

    if (_isConnected) {
      return await disconnect();
    } else {
      return await connect();
    }
  }

  Future<bool> connect() async {
    if (selectedServer == null) {
      debugPrint('VpnController: Cannot connect - no server selected');
      return false;
    }

    final serverToConnect = _selectedServer!;

    _isConnecting = true;
    _status = "Подключение...";
    notifyListeners();

    try {
      debugPrint('VpnController: Connecting to ${serverToConnect.displayName} in ${_vpnMode.name} mode');

      await _coreManager.start(serverToConnect.config, mode: _vpnMode);

      _isConnected = true;
      _status = "Подключено: ${serverToConnect.displayName}";
      await UnifiedStorage.saveLastServer(serverToConnect.id);
      _isConnecting = false;

      debugPrint('VpnController: Connected successfully');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('VpnController: Connection failed: $e');

      _coreManager.stop();
      _isConnecting = false;
      _isConnected = false;
      _status = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> disconnect() async {
    debugPrint('VpnController: Disconnecting...');

    _isConnecting = true;
    _status = "Отключение...";
    notifyListeners();

    try {
      await _coreManager.stop();
      _isConnected = false;
      _status = "Отключено";
      _isConnecting = false;

      debugPrint('VpnController: Disconnected successfully');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('VpnController: Disconnect failed: $e');

      _isConnecting = false;
      _status = "Ошибка отключения";
      notifyListeners();
      return false;
    }
  }

  Future<void> autoConnectToLastServer() async {
    final settings = await SettingsStorage.loadSettings();
    if (!settings.autoConnectLastServer) {
      debugPrint('VpnController: Auto-connect disabled in settings');
      return;
    }

    final lastServerId = await UnifiedStorage.loadLastServerId();
    if (lastServerId == null) {
      debugPrint('VpnController: No last server ID found');
      return;
    }

    final potentialServers = _allServers.where((s) => s.id == lastServerId);
    final ServerItem? lastServer = potentialServers.isNotEmpty ? potentialServers.first : null;

    if (lastServer != null) {
      debugPrint('VpnController: Auto-connecting to last server: ${lastServer.displayName}');
      selectServer(lastServer);
      await connect();
    } else {
      debugPrint('VpnController: Last server not found (ID: $lastServerId)');
    }
  }

  Future<void> addManualServer(String server) async {
    await addServer(server);
  }

  Future<void> addServer(String config) async {
    try {
      debugPrint('VpnController: Adding server...');

      final newServer = await UnifiedStorage.addManualServer(config);
      await loadInitialServers();
      await searchServers(newServer.displayName);
      selectServer(newServer);

      debugPrint('VpnController: Server added: ${newServer.displayName}');
    } catch (e) {
      debugPrint('VpnController: Failed to add server: $e');
      rethrow;
    }
  }

  Future<void> deleteServer(String serverId) async {
    debugPrint('VpnController: Deleting server: $serverId');

    final wasConnected = _isConnected && selectedServer?.id == serverId;
    if (wasConnected) {
      debugPrint('VpnController: Disconnecting from server before deletion');
      await disconnect();
    }

    await UnifiedStorage.deleteServer(serverId);
    await loadInitialServers();

    if (selectedServer?.id == serverId) {
      _selectedServer = null;
      debugPrint('VpnController: Cleared selected server');
    }

    notifyListeners();
  }

  Future<void> toggleFavorite(String serverId) async {
    debugPrint('VpnController: Toggling favorite for server: $serverId');
    await UnifiedStorage.toggleFavorite(serverId);
    await loadInitialServers();
  }

  @override
  void dispose() {
    debugPrint('VpnController: Disposing...');
    _coreManager.removeListener(_onCoreStatusChanged);


    super.dispose();
  }
}