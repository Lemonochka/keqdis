import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Manages a lock file to ensure only one instance of the app is running.
class SingleInstanceManager {
  static const String _lockFileName = '.keqdis.lock';
  static RandomAccessFile? _lock;

  /// Checks if another instance of the application is already running.
  ///
  /// This is more robust than a simple file lock, as it checks if the PID
  /// in the lock file corresponds to a currently running process.
  ///
  /// Returns `true` if another instance is running, `false` otherwise.
  static Future<bool> isAlreadyRunning() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final lockPath = path.join(tempDir.path, _lockFileName);
      final lockFile = File(lockPath);

      if (await lockFile.exists()) {
        final pidInFile = await _getProcessIdFromFile(lockFile);
        if (pidInFile != null && await _isProcessRunning(pidInFile)) {
          // A valid instance is already running.
          debugPrint('SingleInstance: Another instance is running (PID: $pidInFile)');
          return true;
        } else {
          debugPrint('SingleInstance: Stale lock file found, cleaning up...');
          // Lock file is stale, delete it
          try {
            await lockFile.delete();
          } catch (e) {
            debugPrint('SingleInstance: Could not delete stale lock: $e');
          }
        }
      }

      // No running instance found, or the lock file is stale.
      // Attempt to acquire the lock for this instance.
      _lock = await lockFile.open(mode: FileMode.write);

      try {
        await _lock!.lock(FileLock.exclusive);
        // Lock acquired successfully. We are the first/main instance.
        // Write current PID to the file.
        await _lock!.truncate(0);
        await _lock!.setPosition(0);
        await _lock!.writeString(pid.toString());
        await _lock!.flush();
        debugPrint('SingleInstance: Lock acquired (PID: $pid)');
        return false;
      } on FileSystemException catch (e) {
        // Could not acquire the lock, another instance is likely starting up
        // at the exact same time.
        debugPrint('SingleInstance: Could not acquire lock: $e');
        await _lock?.close();
        _lock = null;
        return true;
      }
    } catch (e, s) {
      debugPrint('Error in isAlreadyRunning check: $e\n$s');
      // To be safe, indicate that another instance might be running.
      return true;
    }
  }

  /// Releases the lock file. Should be called on application exit.
  static Future<void> release() async {
    if (_lock == null) return;
    try {
      await _lock!.unlock();
      await _lock!.close();
      debugPrint('SingleInstance: Lock released');

      // Удаляем lock файл при выходе
      try {
        final tempDir = await getTemporaryDirectory();
        final lockPath = path.join(tempDir.path, _lockFileName);
        final lockFile = File(lockPath);
        if (await lockFile.exists()) {
          await lockFile.delete();
          debugPrint('SingleInstance: Lock file deleted');
        }
      } catch (e) {
        debugPrint('SingleInstance: Could not delete lock file: $e');
      }
    } catch (e, s) {
      debugPrint('Error releasing instance lock: $e\n$s');
    } finally {
      _lock = null;
    }
  }

  static Future<int?> _getProcessIdFromFile(File file) async {
    try {
      final content = await file.readAsString();
      final trimmed = content.trim();
      return int.tryParse(trimmed);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        // ✅ ИСПРАВЛЕНИЕ: Используем точный фильтр PID
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/NH'],
          runInShell: false,
        ).timeout(const Duration(seconds: 2));

        // Проверяем что вывод содержит ТОЧНО наш PID
        final output = result.stdout.toString();

        // Разбираем вывод tasklist
        // Формат: ImageName PID SessionName SessionNumber MemUsage
        final lines = output.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;

          // Разбиваем по пробелам и ищем PID
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final pidInLine = int.tryParse(parts[1]);
            if (pidInLine == pid) {
              debugPrint('SingleInstance: Process with PID $pid is running');
              return true;
            }
          }
        }

        debugPrint('SingleInstance: Process with PID $pid is not running');
        return false;

      } else if (Platform.isLinux || Platform.isMacOS) {
        // `ps -p <pid>` has an exit code of 0 if the process exists.
        final result = await Process.run(
          'ps',
          ['-p', pid.toString()],
          runInShell: false,
        ).timeout(const Duration(seconds: 2));

        final isRunning = result.exitCode == 0;
        debugPrint('SingleInstance: Process with PID $pid ${isRunning ? 'is' : 'is not'} running');
        return isRunning;
      }
    } catch (e, s) {
      debugPrint('Error checking if process $pid is running: $e\n$s');
    }
    // Assume not running if the check fails.
    return false;
  }
}