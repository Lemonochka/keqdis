import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class VpnService {
  Process? _process;
  bool _isRunning = false;

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

    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', exeName]);
      }
    } catch (e) {
      // Process may not exist
    }
  }

  Future<void> _prepareAssets() async {
    final dir = await getApplicationSupportDirectory();
    final canonicalDir = path.canonicalize(dir.path);

    for (var fileName in _requiredFiles) {
      if (!_isValidFileName(fileName)) {
        throw SecurityException('Недопустимое имя файла: $fileName');
      }

      final filePath = path.join(dir.path, fileName);
      final canonicalFile = path.canonicalize(filePath);

      if (!canonicalFile.startsWith(canonicalDir)) {
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

          if (Platform.isWindows && fileName.endsWith('.exe')) {
            try {
              await Process.run('icacls', [
                filePath,
                '/inheritance:r',
                '/grant:r',
                '${Platform.environment['USERNAME']}:RX'
              ]);
            } catch (e) {
              // ACL setup failed, continue anyway
            }
          }
        } catch (e) {
          if (fileName.endsWith('.exe')) {
            throw e;
          }
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
      }) async {
    if (_isRunning) return;

    if (!_isValidExecutable(executableName)) {
      throw SecurityException('Попытка запуска запрещенного файла: $executableName');
    }

    await _killExistingProcess(executableName);

    final dir = await getApplicationSupportDirectory();
    final configPath = path.join(dir.path, 'config.json');

    try {
      json.decode(configJson);
    } catch (e) {
      throw ArgumentError('Некорректный JSON конфиг: $e');
    }

    final configFile = File(configPath);
    await configFile.writeAsString(configJson);

    await _prepareAssets();

    final exePath = path.join(dir.path, executableName);

    if (!await File(exePath).exists()) {
      throw Exception('Исполняемый файл $executableName не найден в ${dir.path}');
    }

    try {
      final runArgs = args ?? ['run', '-c', configPath];

      for (final arg in runArgs) {
        if (arg.contains('&') || arg.contains('|')) {
          throw SecurityException('Недопустимые символы в аргументах');
        }
      }

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

      _process?.stdout.transform(utf8.decoder).listen((log) {
        // Output suppressed
      });

      _process?.stderr.transform(utf8.decoder).listen((err) {
        if (err.contains('Failed') || err.contains('panic') || err.contains('FATAL')) {
          _isRunning = false;
        }
      });

      _process?.exitCode.then((code) {
        _isRunning = false;
        _process = null;
      });

    } catch (e) {
      _isRunning = false;
      _process = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    _process?.kill();
    _process = null;
    _isRunning = false;
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}