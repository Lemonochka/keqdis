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
    notifyListeners();
  }

  void _sortServers() {
    _allServers.sort((a, b) {
      // Сначала избранные
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;

      // Затем по имени
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

    // Сортируем результаты поиска тоже
    _searchResults.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    notifyListeners();
  }


  void selectServer(ServerItem server) {
    if (_isConnecting || _isConnected) return;

    _selectedServer = server;
    notifyListeners();
  }

  Future<void> switchVpnMode(VpnMode newMode) async {
    if (_vpnMode == newMode) return;

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
      await disconnect();
      await connect();
    }
  }

  Future<bool> toggleConnection() async {
    if (_isConnecting) return false;

    if (_isConnected) {
      return await disconnect();
    } else {
      return await connect();
    }
  }

  Future<bool> connect() async {
    if (selectedServer == null) return false;

    _isConnecting = true;
    _status = "Подключение...";
    notifyListeners();

    try {
      await _coreManager.start(selectedServer!.config, mode: _vpnMode);

      _isConnected = true;
      _status = "Подключено: ${selectedServer!.displayName}";
      await UnifiedStorage.saveLastServer(selectedServer!.id);
      _isConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _coreManager.stop();
      _isConnecting = false;
      _isConnected = false;
      _status = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> disconnect() async {
    _isConnecting = true;
    _status = "Отключение...";
    notifyListeners();

    try {
      await _coreManager.stop();
      _isConnected = false;
      _status = "Отключено";
      _isConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isConnecting = false;
      _status = "Ошибка отключения";
      notifyListeners();
      return false;
    }
  }

  Future<void> autoConnectToLastServer() async {
    final settings = await SettingsStorage.loadSettings();
    if (!settings.autoConnectLastServer) return;

    final lastServerId = await UnifiedStorage.loadLastServerId();
    if (lastServerId != null) {
      final potentialServers = _allServers.where((s) => s.id == lastServerId);
      final ServerItem? lastServer = potentialServers.isNotEmpty ? potentialServers.first : null;
      if (lastServer != null) {
        selectServer(lastServer);
        await connect();
      }
    }
  }

  Future<void> addManualServer(String server) async {
    await addServer(server);
  }

  Future<void> addServer(String config) async {
    try {
      final newServer = await UnifiedStorage.addManualServer(config);
      await loadInitialServers();
      await searchServers(newServer.displayName);
      selectServer(newServer);
    } catch (e) {
      // Handle error
    }
  }

  Future<void> deleteServer(String serverId) async {
    final wasConnected = _isConnected && selectedServer?.id == serverId;
    if (wasConnected) {
      await disconnect();
    }

    await UnifiedStorage.deleteServer(serverId);
    await loadInitialServers();
    if (selectedServer?.id == serverId) {
      _selectedServer = null;
    }

    notifyListeners();
  }

  Future<void> toggleFavorite(String serverId) async {
    await UnifiedStorage.toggleFavorite(serverId);
    await loadInitialServers();
  }

  @override
  void dispose() {
    _coreManager.removeListener(_onCoreStatusChanged);
    if (_isConnected) {
      disconnect();
    }
    super.dispose();
  }
}
