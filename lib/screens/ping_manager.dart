import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ping_service.dart';
import '../storages/unified_storage.dart';

class PingManager extends ChangeNotifier {
  final Map<String, PingResult> _pingResults = {};
  bool _isPinging = false;

  // Getters
  Map<String, PingResult> get pingResults => _pingResults;
  bool get isPinging => _isPinging;

  Future<void> pingServer(ServerItem server, String pingType) async {
    final key = _getServerKey(server);

    try {
      final type = PingType.values.firstWhere((e) => e.name == pingType);
      final result = await PingService.ping(server.config, type);
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
      final List<Future> pingFutures = [];
      for (final server in servers) {
        onProgress(server, false);
        final future = pingServer(server as ServerItem, pingType).then((_) {
          onProgress(server, true);
        });
        pingFutures.add(future);
      }
      await Future.wait(pingFutures);
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
