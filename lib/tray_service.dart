import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  bool _isInitialized = false;
  Function()? onShow;
  Function()? onToggleConnection;
  Function()? onExit;

  Future<void> initialize({
    required Function() onShowCallback,
    required Function() onToggleCallback,
    required Function() onExitCallback,
  }) async {
    if (_isInitialized) {
      print('Трей уже инициализирован');
      return;
    }

    print('Инициализация трея...');
    onShow = onShowCallback;
    onToggleConnection = onToggleCallback;
    onExit = onExitCallback;

    await trayManager.setIcon(
      'assets/icons/tray_icon.ico',
    );

    await _updateMenu(isConnected: false);
    trayManager.addListener(this);
    _isInitialized = true;
    print('Трей инициализирован успешно');
  }

  Future<void> updateConnectionStatus(bool isConnected) async {
    await _updateMenu(isConnected: isConnected);
  }

  Future<void> _updateMenu({required bool isConnected}) async {
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show',
          label: 'Показать KEQDIS',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'toggle',
          label: isConnected ? 'Отключиться' : 'Подключиться',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: 'Выход',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);

    // Обновляем tooltip
    await trayManager.setToolTip(
        isConnected ? 'KEQDIS - Подключено' : 'KEQDIS - Отключено'
    );
  }

  @override
  void onTrayIconMouseDown() {
    print('Клик по иконке трея');
    onShow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    print('ПКМ по иконке трея');
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    print('Клик по меню трея: ${menuItem.key}');
    switch (menuItem.key) {
      case 'show':
        onShow?.call();
        break;
      case 'toggle':
        onToggleConnection?.call();
        break;
      case 'exit':
        onExit?.call();
        break;
    }
  }

  Future<void> dispose() async {
    print('Disposing трея...');
    trayManager.removeListener(this);
    await trayManager.destroy();
    _isInitialized = false;
    print('Трей уничтожен');
  }
}