import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Менеджер для проверки единственного экземпляра приложения
class SingleInstanceManager {
  static const String _lockFileName = '.keqdis.lock';
  static RandomAccessFile? _lockFile;

  /// Проверить, запущено ли уже приложение
  static Future<bool> isAlreadyRunning() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final lockPath = path.join(tempDir.path, _lockFileName);
      final lockFile = File(lockPath);

      _lockFile = await lockFile.open(mode: FileMode.write);

      try {
        await _lockFile!.lock(FileLock.exclusive);

        await _lockFile!.truncate(0);
        await _lockFile!.setPosition(0);
        await _lockFile!.writeString(pid.toString());
        await _lockFile!.flush();

        return false;
      } catch (e) {
        await _lockFile!.close();
        _lockFile = null;
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  /// Освободить lock файл при выходе
  static Future<void> release() async {
    try {
      if (_lockFile != null) {
        await _lockFile!.unlock();
        await _lockFile!.close();
        _lockFile = null;

        final tempDir = await getTemporaryDirectory();
        final lockPath = path.join(tempDir.path, _lockFileName);
        final lockFile = File(lockPath);
        if (await lockFile.exists()) {
          await lockFile.delete();
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}