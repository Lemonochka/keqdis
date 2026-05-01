import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ping_service.dart';
import '../storages/unified_storage.dart';
import '../storages/improved_settings_storage.dart';

class PingManager extends ChangeNotifier {
  final Map<String, PingResult> _pingResults = {};
  bool _isPinging = false;
  static const int _bulkMaxConcurrent = 12;
  static const int _bulkTimeoutSeconds = 3;

  // Getters
  Map<String, PingResult> get pingResults => _pingResults;
  bool get isPinging => _isPinging;

  Future<void> pingServer(ServerItem server, String pingType) async {
    final key = _getServerKey(server);

    try {
      final type = PingType.values.firstWhere((e) => e.name == pingType);
      // Use current local port for proxy ping instead of hard-coded 2080.
      final settings = await SettingsStorage.loadSettings();
      final result = await PingService.ping(
        server.config,
        type,
        proxyPort: settings.localPort,
      );
      _pingResults[key] = result;
      notifyListeners();
    } catch (e) {
      _pingResults[key] = PingResult(server: server.displayName, success: false);
      notifyListeners();
    }
  }

  Future<void> pingMultipleServers(
    List<dynamic> servers,
    String pingType,
    Function(dynamic server, bool isComplete) onProgress,
  ) async {
    if (_isPinging) return;

    _isPinging = true;
    notifyListeners();

    try {
      final normalizedServers = servers.whereType<ServerItem>().toList();
      if (normalizedServers.isEmpty) return;

      final type = PingType.values.firstWhere((e) => e.name == pingType);
      final settings = await SettingsStorage.loadSettings();
      final proxyPort = settings.localPort;

      for (final server in normalizedServers) {
        onProgress(server, false);
      }

      final total = normalizedServers.length;
      final workersCount = total < _bulkMaxConcurrent
          ? total
          : _bulkMaxConcurrent;
      int nextIndex = 0;

      Future<void> worker() async {
        while (true) {
          if (nextIndex >= total) return;
          final currentIndex = nextIndex++;
          final server = normalizedServers[currentIndex];
          final key = _getServerKey(server);
          try {
            final result = await PingService.ping(
              server.config,
              type,
              proxyPort: proxyPort,
              timeoutSeconds: _bulkTimeoutSeconds,
            ).timeout(const Duration(seconds: _bulkTimeoutSeconds + 1));
            _pingResults[key] = result;
          } on TimeoutException {
            _pingResults[key] = PingResult(
              server: server.displayName,
              success: false,
              error: 'Превышено время ожидания',
            );
          } catch (_) {
            _pingResults[key] = PingResult(
              server: server.displayName,
              success: false,
              error: 'Ошибка пинга',
            );
          } finally {
            onProgress(server, true);
            notifyListeners();
          }
        }
      }

      await Future.wait(List.generate(workersCount, (_) => worker()));
    } finally {
      _isPinging = false;
      notifyListeners();
    }
  }

  PingResult? getPingResult(ServerItem server) {
    final key = _getServerKey(server);
    return _pingResults[key];
  }

  void clearPingResults() {
    _pingResults.clear();
    notifyListeners();
  }

  String _getServerKey(ServerItem server) {
    return server.id;
  }

  @override
  void dispose() {
    _pingResults.clear();
    super.dispose();
  }
}
