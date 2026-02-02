import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class VpnService {
  Process? _process;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  // ОБНОВЛЕНО: Добавлены sing-box.exe и wintun.dll
  final List<String> _requiredFiles = [
    'xray.exe',
    'sing-box.exe',
    'wintun.dll',
    'geoip.dat',
    'geosite.dat'
  ];

  /// БЕЗОПАСНОСТЬ: Валидация имени процесса
  bool _isValidExecutable(String exeName) {
    // Разрешаем только наши бинарники
    return exeName == 'xray.exe' || exeName == 'sing-box.exe';
  }

  /// БЕЗОПАСНОСТЬ: Завершение конкретного типа процессов перед запуском
  Future<void> _killExistingProcess(String exeName) async {
    if (!_isValidExecutable(exeName)) {
      throw ArgumentError('Недопустимое имя процесса для очистки: $exeName');
    }

    try {
      // Убиваем только процессы с таким же именем (чтобы xray не убил sing-box)
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', exeName]);
      }
    } catch (e) {
      // Игнорируем, если процесс не был запущен
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
          // Пытаемся загрузить. Если файла нет в assets (например wintun),
          // приложение может упасть, поэтому оборачиваем в try
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
              print('Warning ACL: $e');
            }
          }
          print("📦 Распакован: $fileName");
        } catch (e) {
          // Если wintun.dll или dat файлы не найдены в ассетах — не критично,
          // но exe файлы обязаны быть.
          if (fileName.endsWith('.exe')) {
            print("❌ Ошибка распаковки критического файла $fileName: $e");
            throw e;
          } else {
            print("⚠️ Пропущен файл $fileName (не найден в assets): $e");
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

  /// Получить директорию с бинарниками (нужно для wintun.dll)
  Future<String> getXrayDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// ОБНОВЛЕНО: Теперь принимает имя файла и аргументы
  Future<void> start(
      String configJson, {
        String executableName = 'xray.exe',
        List<String>? args,
      }) async {
    if (_isRunning) return;

    // Проверка безопасности имени файла
    if (!_isValidExecutable(executableName)) {
      throw SecurityException('Попытка запуска запрещенного файла: $executableName');
    }

    // Чистим старые процессы именно этого типа
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

    // Распаковываем всё необходимое (xray, sing-box, wintun)
    await _prepareAssets();

    final exePath = path.join(dir.path, executableName);

    if (!await File(exePath).exists()) {
      throw Exception('Исполняемый файл $executableName не найден в ${dir.path}');
    }

    try {
      // Формируем аргументы.
      // Если args не переданы, используем дефолт для Xray (run -c config)
      // Для Sing-box мы будем передавать args явно из CoreManager
      final runArgs = args ?? ['run', '-c', configPath];

      // Валидация аргументов
      for (final arg in runArgs) {
        if (arg.contains('&') || arg.contains('|')) {
          throw SecurityException('Недопустимые символы в аргументах');
        }
      }

      print('🚀 Запуск $executableName с аргументами: $runArgs');

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

      // Логирование
      _process?.stdout.transform(utf8.decoder).listen((log) {
        // Убрали сильное ограничение длины для отладки, но оставили разумное
        if (log.length > 500) {
          print("[$executableName]: ${log.substring(0, 500)}...");
        } else {
          print("[$executableName]: ${log.trim()}");
        }
      });

      _process?.stderr.transform(utf8.decoder).listen((err) {
        print("[$executableName ERR]: $err");
        if (err.contains('Failed') || err.contains('panic') || err.contains('FATAL')) {
          _isRunning = false;
        }
      });

      _process?.exitCode.then((code) {
        print("$executableName завершился с кодом: $code");
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
    // Мягкая остановка текущего процесса инстанса
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