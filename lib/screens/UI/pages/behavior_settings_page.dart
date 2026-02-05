import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/services/autostart_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';

class BehaviorSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const BehaviorSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  bool _autoStart = false;
  bool _minimizeToTray = true;
  bool _startMinimized = false;
  bool _autoConnectLastServer = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _autoStart = settings.autoStart;
        _minimizeToTray = settings.minimizeToTray;
        _startMinimized = settings.startMinimized;
        _autoConnectLastServer = settings.autoConnectLastServer;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: currentSettings.pingType,
      autoStart: _autoStart,
      minimizeToTray: _minimizeToTray,
      startMinimized: _startMinimized,
      autoConnectLastServer: _autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);
    await AutoStartService.toggle(_autoStart);

    widget.onSettingsChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: 'Настройки сохранены',
        type: NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Scaffold(
      body: Stack(
        children: [
          // Кастомный фон
          if (themeManager.hasCustomBackground)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(themeManager.settings.backgroundImagePath!),
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: themeManager.settings.blurIntensity,
                      sigmaY: themeManager.settings.blurIntensity,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(
                        1.0 - themeManager.settings.backgroundOpacity,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Контент
          Column(
            children: [
              AppBar(
                backgroundColor: themeManager.settings.accentColor.withOpacity(0.9),
                title: const Text('Поведение приложения'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Card(
                            color: themeManager.settings.accentColor.withOpacity(0.3),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('Автозапуск'),
                                  subtitle: const Text(
                                    'Запускать приложение при старте системы',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  value: _autoStart,
                                  activeColor: themeManager.settings.primaryColor,
                                  onChanged: (value) {
                                    setState(() => _autoStart = value);
                                    _saveSettings();
                                  },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('Сворачивать в трей'),
                                  subtitle: const Text(
                                    'При закрытии окна сворачивать в системный трей',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  value: _minimizeToTray,
                                  activeColor: themeManager.settings.primaryColor,
                                  onChanged: (value) {
                                    setState(() => _minimizeToTray = value);
                                    _saveSettings();
                                  },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('Стартовать свернутым'),
                                  subtitle: const Text(
                                    'Запускать приложение свернутым в трей',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  value: _startMinimized,
                                  activeColor: themeManager.settings.primaryColor,
                                  onChanged: (value) {
                                    setState(() => _startMinimized = value);
                                    _saveSettings();
                                  },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('Автоподключение'),
                                  subtitle: const Text(
                                    'Подключаться к последнему серверу при старте',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  value: _autoConnectLastServer,
                                  activeColor: themeManager.settings.primaryColor,
                                  onChanged: (value) {
                                    setState(() => _autoConnectLastServer = value);
                                    _saveSettings();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
