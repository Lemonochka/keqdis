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
      
      // Пытаемся создать lock файл с эксклюзивным доступом
      _lockFile = await lockFile.open(mode: FileMode.write);
      
      // Пытаемся захватить эксклюзивную блокировку
      try {
        await _lockFile!.lock(FileLock.exclusive);
        
        // Записываем PID текущего процесса
        await _lockFile!.truncate(0);
        await _lockFile!.setPosition(0);
        await _lockFile!.writeString(pid.toString());
        await _lockFile!.flush();
        
        print('Lock файл создан успешно: $lockPath');
        return false; // Приложение НЕ запущено
      } catch (e) {
        print('Не удалось захватить блокировку: $e');
        await _lockFile!.close();
        _lockFile = null;
        return true; // Приложение УЖЕ запущено
      }
    } catch (e) {
      print('Ошибка проверки single instance: $e');
      return false; // В случае ошибки разрешаем запуск
    }
  }
  
  /// Освободить lock файл при выходе
  static Future<void> release() async {
    try {
      if (_lockFile != null) {
        await _lockFile!.unlock();
        await _lockFile!.close();
        _lockFile = null;
        
        // Удаляем lock файл
        final tempDir = await getTemporaryDirectory();
        final lockPath = path.join(tempDir.path, _lockFileName);
        final lockFile = File(lockPath);
        if (await lockFile.exists()) {
          await lockFile.delete();
        }
        
        print('Lock файл освобожден');
      }
    } catch (e) {
      print('Ошибка освобождения lock: $e');
    }
  }
}
