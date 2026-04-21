import 'package:flutter/foundation.dart';

class DebugLogService extends ChangeNotifier {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  static const int _maxEntries = 1000;

  final List<String> _entries = <String>[];
  DebugPrintCallback? _originalDebugPrint;
  bool _isInstalled = false;

  List<String> get entries => List.unmodifiable(_entries);

  void installDebugPrintHook() {
    if (_isInstalled) return;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.isNotEmpty) {
        addLog(message);
      }
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    };
    _isInstalled = true;
  }

  void addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _entries.add('[$timestamp] $message');
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
