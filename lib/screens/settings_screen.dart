import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../improved_theme_manager.dart';
import '../improved_settings_storage.dart';
import '../autostart_service.dart';
import '../custom_notification.dart';
import 'improved_routing_settings.dart';

class SettingsView extends StatefulWidget {
  final VoidCallback? onThemeChanged;
  final VoidCallback? onSettingsChanged;

  const SettingsView({super.key, this.onThemeChanged, this.onSettingsChanged});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late Future<AppSettings> _settingsFuture;
  final _portCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsFuture = SettingsStorage.loadSettings().then((s) {
      if (mounted) {
        _portCtrl.text = s.localPort.toString();
      }
      return s;
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePort() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: int.tryParse(_portCtrl.text) ?? 2080,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: currentSettings.pingType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    widget.onSettingsChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: 'Локальный порт сохранен. Переподключитесь для применения.',
        type: NotificationType.success,
      );
    }
  }

  Widget _buildMenuCard(
      String title,
      String subtitle,
      IconData icon,
      VoidCallback onTap,
      ) {
    final themeManager = ThemeManager();
    return Card(
      color: themeManager.settings.accentColor.withOpacity(0.3),
      child: ListTile(
        leading: Icon(icon, color: themeManager.settings.primaryColor, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Icon(Icons.arrow_forward_ios, color: themeManager.settings.secondaryColor),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // === ЛОКАЛЬНЫЙ ПОРТ ===
            Text(
              "Основные настройки",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            Card(
              color: themeManager.settings.accentColor.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Локальный порт",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "Например: 2080",
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _savePort,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeManager.settings.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          ),
                          child: const Text(
                            "Сохранить",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // === ПОДМЕНЮ ===
            Text(
              "Дополнительные настройки",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            _buildMenuCard(
              "Поведение приложения",
              "Автозапуск, свертывание в трей и другое",
              Icons.settings_applications,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BehaviorSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              "Маршрутизация",
              "Правила для доменов, IP-адресов и блокировки",
              Icons.route,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ImprovedRoutingSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              "Настройки пинга",
              "Выбор типа пинга (TCP или через прокси)",
              Icons.speed,
                  () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PingSettingsPage(onSettingsChanged: widget.onSettingsChanged)),
                );
              },
            ),

            const SizedBox(height: 32),

            // === ВНЕШНИЙ ВИД ===
            Text(
              "Внешний вид",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeManager.settings.primaryColor,
              ),
            ),
            const SizedBox(height: 16),

            AnimatedBuilder(
              animation: themeManager,
              builder: (context, child) {
                return Card(
                  color: themeManager.settings.accentColor.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (themeManager.hasCustomBackground) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                Image.file(
                                  File(themeManager.settings.backgroundImagePath!),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    onPressed: () async {
                                      await themeManager.removeBackground();
                                      widget.onThemeChanged?.call();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          Text("Прозрачность фона", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          Slider(
                            value: themeManager.settings.backgroundOpacity,
                            min: 0.1,
                            max: 0.9,
                            divisions: 8,
                            label: '${(themeManager.settings.backgroundOpacity * 100).round()}%',
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              themeManager.updateOpacity(value);
                            },
                            onChangeEnd: (value) {
                              themeManager.saveTheme();
                            },
                          ),

                          const SizedBox(height: 8),
                          Text("Размытие фона", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          Slider(
                            value: themeManager.settings.blurIntensity,
                            min: 0,
                            max: 30,
                            divisions: 30,
                            label: themeManager.settings.blurIntensity.round().toString(),
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              themeManager.updateBlur(value);
                            },
                            onChangeEnd: (value) {
                              themeManager.saveTheme();
                            },
                          ),

                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                        ],

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await themeManager.pickBackgroundImage();
                              widget.onThemeChanged?.call();
                            },
                            icon: const Icon(Icons.image),
                            label: Text(themeManager.hasCustomBackground
                                ? "Изменить фон"
                                : "Выбрать фоновое изображение"
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: themeManager.settings.primaryColor,
                              side: BorderSide(color: themeManager.settings.primaryColor),
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        Text(
                          "Цвета интерфейса автоматически адаптируются под выбранное изображение",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}
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

  Future<void> _saveBehaviorSettings() async {
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

    if (mounted) {
      widget.onSettingsChanged?.call();
    }
  }

  Widget _buildSwitch(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Card(
      color: ThemeManager().settings.accentColor.withOpacity(0.3),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        value: value,
        activeColor: ThemeManager().settings.primaryColor,
        onChanged: onChanged,
      ),
    );
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
                          1.0 - themeManager.settings.backgroundOpacity
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
                    _buildSwitch(
                      "Автозапуск при старте",
                      "Приложение будет запускаться вместе с системой",
                      _autoStart,
                          (value) {
                        setState(() => _autoStart = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Сворачивать в трей",
                      "Приложение будет сворачиваться в трей",
                      _minimizeToTray,
                          (value) {
                        setState(() => _minimizeToTray = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Запускать свёрнутым",
                      "Приложение будет сразу сворачиваться в трей при автозапуске",
                      _startMinimized,
                          (value) {
                        setState(() => _startMinimized = value);
                        _saveBehaviorSettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitch(
                      "Автоподключение к последнему серверу",
                      "Автоматически подключаться к последнему использованному серверу при запуске",
                      _autoConnectLastServer,
                          (value) {
                        setState(() => _autoConnectLastServer = value);
                        _saveBehaviorSettings();
                      },
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

// === СТРАНИЦА: НАСТРОЙКИ МАРШРУТИЗАЦИИ ===

class RoutingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const RoutingSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<RoutingSettingsPage> createState() => _RoutingSettingsPageState();
}

class _RoutingSettingsPageState extends State<RoutingSettingsPage> {
  final _directDomainsCtrl = TextEditingController();
  final _blockDomainsCtrl = TextEditingController();
  final _directIpsCtrl = TextEditingController();
  final _proxyDomainsCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _directDomainsCtrl.dispose();
    _blockDomainsCtrl.dispose();
    _directIpsCtrl.dispose();
    _proxyDomainsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _directDomainsCtrl.text = settings.directDomains;
        _blockDomainsCtrl.text = settings.blockedDomains;
        _directIpsCtrl.text = settings.directIps;
        _proxyDomainsCtrl.text = settings.proxyDomains;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRoutingSettings() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: _directDomainsCtrl.text,
      blockedDomains: _blockDomainsCtrl.text,
      directIps: _directIpsCtrl.text,
      proxyDomains: _proxyDomainsCtrl.text,
      pingType: currentSettings.pingType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    if (mounted) {
      widget.onSettingsChanged?.call();

      CustomNotification.show(
        context,
        message: 'Настройки маршрутизации сохранены. Переподключитесь для применения.',
        type: NotificationType.success,
      );
    }
  }

  Widget _buildField(String label, String hint, TextEditingController ctrl, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
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
                          1.0 - themeManager.settings.backgroundOpacity
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
                title: const Text('Настройки маршрутизации'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      "Можно вводить через запятую, пробел или с новой строки.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Сайты напрямую (Direct)",
                      "yandex.ru, vk.com, ru...",
                      _directDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Принудительно через VPN",
                      "google.com, youtube.com...",
                      _proxyDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "Блокировка сайтов (Block)",
                      "ads.google.com, tracker.com...",
                      _blockDomainsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      "IP напрямую (CIDR)",
                      "192.168.0.0/16, 10.0.0.0/8...",
                      _directIpsCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveRoutingSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeManager.settings.primaryColor,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save, size: 24),
                            SizedBox(width: 12),
                            Text("Сохранить настройки"),
                          ],
                        ),
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

// === СТРАНИЦА: НАСТРОЙКИ ПИНГА ===

class PingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const PingSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<PingSettingsPage> createState() => _PingSettingsPageState();
}

class _PingSettingsPageState extends State<PingSettingsPage> {
  String _pingType = 'tcp';
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
        _pingType = settings.pingType;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePingSettings(String newType) async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: currentSettings.directDomains,
      blockedDomains: currentSettings.blockedDomains,
      directIps: currentSettings.directIps,
      proxyDomains: currentSettings.proxyDomains,
      pingType: newType,
      autoStart: currentSettings.autoStart,
      minimizeToTray: currentSettings.minimizeToTray,
      startMinimized: currentSettings.startMinimized,
      autoConnectLastServer: currentSettings.autoConnectLastServer,
    );

    await SettingsStorage.saveSettings(settings);

    if (mounted) {
      widget.onSettingsChanged?.call();
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
                          1.0 - themeManager.settings.backgroundOpacity
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
                backgroundColor: themeManager.settings.accentColor.withOpacity(
                    0.9),
                title: const Text('Настройки пинга'),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      "Тип пинга",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: themeManager.settings.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: themeManager.settings.accentColor.withOpacity(0.3),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Text('TCP пинг'),
                            subtitle: const Text(
                              'Прямое подключение к серверу',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            value: 'tcp',
                            groupValue: _pingType,
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              setState(() => _pingType = value!);
                              _savePingSettings(value!);
                            },
                          ),
                          const Divider(height: 1),
                          RadioListTile<String>(
                            title: const Text('Пинг Прокси'),
                            subtitle: const Text(
                              'Проверка через локальный прокси',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            value: 'proxy',
                            groupValue: _pingType,
                            activeColor: themeManager.settings.primaryColor,
                            onChanged: (value) {
                              setState(() => _pingType = value!);
                              _savePingSettings(value!);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue,
                                  size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Подсказка',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '• TCP пинг - для проверки удалённости от серверов\n'
                                '• Пинг через прокси - используйте для проверки доступности сервера',
                            style: TextStyle(fontSize: 13, height: 1.5),
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