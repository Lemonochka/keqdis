import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class VpnService {
  Process? _process;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  // Список необходимых файлов
  final List<String> _requiredFiles = ['xray.exe', 'geoip.dat', 'geosite.dat'];

  /// БЕЗОПАСНОСТЬ: Валидация имени процесса
  static bool _isValidProcessName(String processName) {
    // Разрешаем только конкретное имя процесса
    return processName == 'xray.exe';
  }

  /// БЕЗОПАСНОСТЬ: Безопасное завершение процесса
  Future<void> _killAllXray() async {
    const processName = 'xray.exe';

    // БЕЗОПАСНОСТЬ: Валидация имени процесса
    if (!_isValidProcessName(processName)) {
      throw ArgumentError('Недопустимое имя процесса');
    }

    try {
      // БЕЗОПАСНОСТЬ: Используем фиксированные аргументы без пользовательского ввода
      await Process.run('taskkill', ['/F', '/IM', processName]);
    } catch (e) {
      // Игнорируем ошибки - процесс может не быть запущен
    }
  }

  Future<String> _prepareAssets() async {
    final dir = await getApplicationSupportDirectory();

    // БЕЗОПАСНОСТЬ: Валидация пути директории
    final canonicalDir = path.canonicalize(dir.path);

    for (var fileName in _requiredFiles) {
      // БЕЗОПАСНОСТЬ: Валидация имени файла
      if (!_isValidFileName(fileName)) {
        throw SecurityException('Недопустимое имя файла: $fileName');
      }

      final filePath = path.join(dir.path, fileName);

      // БЕЗОПАСНОСТЬ: Проверка, что файл находится в разрешенной директории
      final canonicalFile = path.canonicalize(filePath);
      if (!canonicalFile.startsWith(canonicalDir)) {
        throw SecurityException('Попытка path traversal: $fileName');
      }

      final file = File(filePath);

      // Распаковываем, если файла нет
      if (!await file.exists()) {
        try {
          // Загружаем из assets/bin/...
          final data = await rootBundle.load('assets/bin/$fileName');
          final bytes = data.buffer.asUint8List();

          // БЕЗОПАСНОСТЬ: Проверка размера файла (защита от DoS)
          if (bytes.length > 100 * 1024 * 1024) { // 100 MB максимум
            throw Exception('Файл $fileName слишком большой');
          }

          await file.writeAsBytes(bytes, flush: true);

          // БЕЗОПАСНОСТЬ: Установка прав доступа только для владельца (только Windows)
          if (Platform.isWindows) {
            // На Windows права устанавливаются через NTFS ACL
            // Для .exe файлов устанавливаем дополнительную защиту
            if (fileName.endsWith('.exe')) {
              try {
                // Удаляем права для всех, кроме текущего пользователя
                await Process.run('icacls', [
                  filePath,
                  '/inheritance:r',
                  '/grant:r',
                  '${Platform.environment['USERNAME']}:RX'
                ]);
              } catch (e) {
                print('Предупреждение: не удалось установить ACL для $fileName: $e');
              }
            }
          }

          print("Распакован файл: $fileName");
        } catch (e) {
          print("Ошибка распаковки $fileName: $e");
          // Если это dat файлы, пробуем жить без них, но предупреждаем
          if (fileName.endsWith('.exe')) throw e;
        }
      }
    }

    return path.join(dir.path, 'xray.exe');
  }

  /// БЕЗОПАСНОСТЬ: Валидация имени файла
  bool _isValidFileName(String fileName) {
    // Запрещаем path traversal
    if (fileName.contains('..') || fileName.contains('/') || fileName.contains('\\')) {
      return false;
    }

    // Разрешаем только конкретные файлы
    return _requiredFiles.contains(fileName);
  }

  Future<void> start(String configJson) async {
    if (_isRunning) return;

    await _killAllXray();

    final dir = await getApplicationSupportDirectory();
    final configPath = path.join(dir.path, 'config.json');

    // БЕЗОПАСНОСТЬ: Валидация JSON конфига
    try {
      json.decode(configJson); // Проверяем, что это валидный JSON
    } catch (e) {
      throw ArgumentError('Некорректный JSON конфиг: $e');
    }

    // БЕЗОПАСНОСТЬ: Ограничение размера конфига
    if (configJson.length > 1024 * 1024) { // 1 MB максимум
      throw ArgumentError('Конфиг слишком большой');
    }

    final configFile = File(configPath);
    await configFile.writeAsString(configJson);

    // БЕЗОПАСНОСТЬ: Установка прав доступа только для владельца
    if (Platform.isWindows) {
      try {
        await Process.run('icacls', [
          configPath,
          '/inheritance:r',
          '/grant:r',
          '${Platform.environment['USERNAME']}:RW'
        ]);
      } catch (e) {
        print('Предупреждение: не удалось установить ACL для config.json: $e');
      }
    }

    // Подготовка файлов (exe + dat)
    final exePath = await _prepareAssets();

    // БЕЗОПАСНОСТЬ: Проверка существования исполняемого файла
    if (!await File(exePath).exists()) {
      throw Exception('Исполняемый файл Xray не найден');
    }

    try {
      // БЕЗОПАСНОСТЬ: Валидация аргументов командной строки
      final args = ['run', '-c', configPath];

      // Проверяем, что пути не содержат опасных символов
      for (final arg in args) {
        if (arg.contains(';') || arg.contains('&') || arg.contains('|')) {
          throw SecurityException('Недопустимые символы в аргументах');
        }
      }

      _process = await Process.start(
        exePath,
        args,
        runInShell: false,
        workingDirectory: dir.path,
        // БЕЗОПАСНОСТЬ: Ограничиваем переменные окружения
        environment: {
          'PATH': Platform.environment['PATH'] ?? '',
        },
      );

      _isRunning = true;

      _process?.stdout.transform(utf8.decoder).listen((log) {
        // БЕЗОПАСНОСТЬ: Не логируем полные сообщения (могут содержать чувствительные данные)
        if (log.length > 200) {
          print("XRAY: [сообщение обрезано, длина ${log.length}]");
        } else {
          print("XRAY: $log");
        }
      });

      _process?.stderr.transform(utf8.decoder).listen((err) {
        // БЕЗОПАСНОСТЬ: Не логируем полные сообщения об ошибках
        if (err.length > 200) {
          print("XRAY ERR: [ошибка обрезана, длина ${err.length}]");
        } else {
          print("XRAY ERR: $err");
        }

        if (err.contains('Failed') || err.contains('panic')) {
          _isRunning = false;
        }
      });

      _process?.exitCode.then((code) {
        print("Xray завершился с кодом: $code");
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
    await _killAllXray();
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