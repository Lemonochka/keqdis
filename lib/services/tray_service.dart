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
    if (_isInitialized) return;

    onShow = onShowCallback;
    onToggleConnection = onToggleCallback;
    onExit = onExitCallback;

    await trayManager.setIcon('assets/icons/tray_icon.ico');
    await _updateMenu(isConnected: false);
    trayManager.addListener(this);
    _isInitialized = true;
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
    await trayManager.setToolTip(
        isConnected ? 'KEQDIS - Подключено' : 'KEQDIS - Отключено'
    );
  }

  @override
  void onTrayIconMouseDown() {
    onShow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
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
    trayManager.removeListener(this);
    await trayManager.destroy();
    _isInitialized = false;
  }
}