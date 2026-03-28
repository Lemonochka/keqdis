import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class VpnService {
  Process? _process;
  bool _isRunning = false;

  // FIX: Сохраняем подписки чтобы отменять при stop() — устраняет утечку памяти
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  // FIX: Callback для оповещения CoreManager об изменении состояния
  VoidCallback? onStateChanged;

  // Конструктор БЕЗ ИЗМЕНЕНИЙ — полная совместимость с существующим кодом
  VpnService();

  bool get isRunning => _isRunning;

  final List<String> _requiredFiles = [
    'xray.exe',
    'sing-box.exe',
    'wintun.dll',
    'geoip.dat',
    'geosite.dat'
  ];

  bool _isValidExecutable(String exeName) {
    return exeName == 'xray.exe' || exeName == 'sing-box.exe';
  }

  Future<void> _killExistingProcess(String exeName) async {
    if (!_isValidExecutable(exeName)) {
      throw ArgumentError('Недопустимое имя процесса для очистки: $exeName');
    }

    if (!Platform.isWindows) return;

    try {
      debugPrint('VpnService: Attempting to kill $exeName...');

      final result = await Process.run(
        'taskkill',
        ['/F', '/IM', exeName],
        runInShell: false,
      ).timeout(const Duration(seconds: 3));

      if (result.exitCode == 0) {
        debugPrint('VpnService: $exeName killed successfully');
        await Future.delayed(const Duration(milliseconds: 500));
        await _waitForProcessToTerminate(exeName, maxWaitSeconds: 3);
      } else {
        debugPrint('VpnService: $exeName not running (exit code: ${result.exitCode})');
      }
    } catch (e) {
      debugPrint('VpnService: Kill process info: $e');
    }
  }

  Future<void> _waitForProcessToTerminate(String exeName, {int maxWaitSeconds = 5}) async {
    final maxAttempts = maxWaitSeconds * 4;

    for (int i = 0; i < maxAttempts; i++) {
      try {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'IMAGENAME eq $exeName'],
          runInShell: false,
        ).timeout(const Duration(seconds: 1));

        if (!result.stdout.toString().contains(exeName)) {
          debugPrint('VpnService: $exeName terminated successfully');
          return;
        }

        await Future.delayed(const Duration(milliseconds: 250));
      } catch (e) {
        debugPrint('VpnService: Process check failed, assuming terminated: $e');
        return;
      }
    }

    debugPrint('VpnService: Warning - $exeName may still be running after $maxWaitSeconds seconds');
  }

  Future<void> _prepareAssets() async {
    final dir = await getApplicationSupportDirectory();

    for (var fileName in _requiredFiles) {
      if (!_isValidFileName(fileName)) {
        throw SecurityException('Недопустимое имя файла: $fileName');
      }

      final filePath = path.join(dir.path, fileName);

      if (!filePath.startsWith(dir.path)) {
        throw SecurityException('Попытка path traversal: $fileName');
      }

      final file = File(filePath);

      if (!await file.exists()) {
        try {
          final data = await rootBundle.load('assets/bin/$fileName');
          final bytes = data.buffer.asUint8List();

          if (bytes.length > 100 * 1024 * 1024) {
            throw Exception('Файл $fileName слишком большой');
          }

          await file.writeAsBytes(bytes, flush: true);
          debugPrint('VpnService: Extracted $fileName (${bytes.length} bytes)');

          if (Platform.isWindows && fileName.endsWith('.exe')) {
            try {
              await Process.run('icacls', [
                filePath,
                '/inheritance:r',
                '/grant:r',
                '${Platform.environment['USERNAME']}:RX'
              ]);
              debugPrint('VpnService: Set permissions for $fileName');
            } catch (e) {
              debugPrint('VpnService: Could not set ACL for $fileName: $e');
            }
          }
        } catch (e) {
          if (fileName.endsWith('.exe')) {
            throw Exception('Не удалось подготовить $fileName: $e');
          }
          debugPrint('VpnService: Optional file $fileName not found: $e');
        }
      }
    }
  }

  bool _isValidFileName(String fileName) {
    if (fileName.contains('..') || fileName.contains('/') || fileName.contains('\\')) {
      return false;
    }
    return _requiredFiles.contains(fileName);
  }

  Future<String> getXrayDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<void> start(
      String configJson, {
        String executableName = 'xray.exe',
        List<String>? args,
        // FIX: Опциональный параметр — имя файла конфига. По умолчанию config.json.
        // Это позволяет xray и sing-box писать в разные файлы.
        String configFileName = 'config.json',
      }) async {
    if (_isRunning) {
      debugPrint('VpnService: Service already running, stopping first...');
      await stop();
    }

    if (!_isValidExecutable(executableName)) {
      throw SecurityException('Попытка запуска запрещенного файла: $executableName');
    }

    await _killExistingProcess(executableName);

    final dir = await getApplicationSupportDirectory();
    // FIX: Используем переданное имя файла вместо жёсткого 'config.json'
    final configPath = path.join(dir.path, configFileName);

    try {
      json.decode(configJson);
    } catch (e) {
      throw ArgumentError('Некорректный JSON конфиг: $e');
    }

    final configFile = File(configPath);
    await configFile.writeAsString(configJson);
    debugPrint('VpnService: Config written to $configPath');

    await _prepareAssets();

    final exePath = path.join(dir.path, executableName);

    if (!await File(exePath).exists()) {
      throw Exception('Исполняемый файл $executableName не найден в ${dir.path}');
    }

    try {
      final runArgs = args ?? ['run', '-c', configPath];

      for (final arg in runArgs) {
        if (arg.contains('&') || arg.contains('|') || arg.contains(';')) {
          throw SecurityException('Недопустимые символы в аргументах: $arg');
        }
      }

      debugPrint('VpnService: Starting $executableName with args: $runArgs');

      _process = await Process.start(
        exePath,
        runArgs,
        runInShell: false,
        workingDirectory: dir.path,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '',
        },
      );

      _isRunning = true;
      debugPrint('VpnService: Process started (PID: ${_process?.pid})');

      // FIX: Сохраняем подписки для последующей отмены
      _stdoutSub = _process?.stdout.transform(utf8.decoder).listen((log) {
        if (kDebugMode) {
          debugPrint('[$executableName] $log');
        }
      });

      _stderrSub = _process?.stderr.transform(utf8.decoder).listen((err) {
        debugPrint('[$executableName ERROR] $err');

        if (err.contains('Failed') || err.contains('panic') || err.contains('FATAL')) {
          debugPrint('VpnService: Critical error detected, marking as not running');
          _isRunning = false;
          // FIX: Оповещаем CoreManager
          onStateChanged?.call();
        }
      });

      _process?.exitCode.then((code) {
        debugPrint('VpnService: Process exited with code $code');
        _isRunning = false;
        _process = null;
        // FIX: Оповещаем CoreManager
        onStateChanged?.call();
      });

      // FIX: Проверяем что ядро не упало сразу (невалидный конфиг и т.д.)
      await Future.delayed(const Duration(milliseconds: 800));
      if (!_isRunning || _process == null) {
        throw Exception('$executableName завершился сразу после запуска — проверьте конфигурацию');
      }

    } catch (e, s) {
      debugPrint('VpnService: Failed to start process: $e\n$s');
      _isRunning = false;
      _process = null;
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      _stdoutSub = null;
      _stderrSub = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isRunning && _process == null) {
      debugPrint('VpnService: Service not running, nothing to stop');
      return;
    }

    debugPrint('VpnService: Stopping service...');

    // FIX: Отменяем stream-подписки — предотвращает утечку памяти
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    try {
      final pid = _process?.pid;

      // FIX: На Windows SIGTERM не работает — используем taskkill
      if (Platform.isWindows && pid != null) {
        final result = await Process.run(
          'taskkill', ['/PID', '$pid'],
          runInShell: false,
        ).timeout(const Duration(seconds: 2), onTimeout: () {
          return ProcessResult(pid, -1, '', 'timeout');
        });

        if (result.exitCode != 0) {
          debugPrint('VpnService: Graceful stop failed, forcing kill...');
          await Process.run(
            'taskkill', ['/F', '/PID', '$pid'],
            runInShell: false,
          ).timeout(const Duration(seconds: 2), onTimeout: () {
            return ProcessResult(pid, -1, '', 'timeout');
          });
        }
      } else {
        // Linux/macOS
        _process?.kill(ProcessSignal.sigterm);
        try {
          await _process?.exitCode.timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              _process?.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        } catch (e) {
          debugPrint('VpnService: Error waiting for exit: $e');
        }
      }

      debugPrint('VpnService: Process stopped');
    } catch (e, s) {
      debugPrint('VpnService: Error during stop: $e\n$s');
    } finally {
      _process = null;
      _isRunning = false;
    }
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}
