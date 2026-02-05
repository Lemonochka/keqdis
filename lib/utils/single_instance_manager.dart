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
          return true;
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
        return false;
      } on FileSystemException {
        // Could not acquire the lock, another instance is likely starting up
        // at the exact same time.
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
      // The file is left behind, but it's fine since we check the PID on startup.
      // Deleting it could cause a race condition if another process starts immediately.
    } catch (e, s) {
      debugPrint('Error releasing instance lock: $e\n$s');
    } finally {
      _lock = null;
    }
  }

  static Future<int?> _getProcessIdFromFile(File file) async {
    try {
      final content = await file.readAsString();
      return int.tryParse(content);
    } catch (e) {
      return null;
    }
  }

  static Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'PID eq $pid']);
        // Check if stdout contains the PID, as tasklist has headers.
        return result.stdout.toString().contains(pid.toString());
      } else if (Platform.isLinux || Platform.isMacOS) {
        // `ps -p <pid>` has an exit code of 0 if the process exists.
        final result = await Process.run('ps', ['-p', pid.toString()]);
        return result.exitCode == 0;
      }
    } catch (e, s) {
      debugPrint('Error checking if process $pid is running: $e\n$s');
    }
    // Assume not running if the check fails.
    return false;
  }
}
