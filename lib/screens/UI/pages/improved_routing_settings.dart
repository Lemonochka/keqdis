import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'app_routing_page.dart';

class ImprovedRoutingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool isVpnConnected;
  final VoidCallback? onReconnectRequest;

  const ImprovedRoutingSettingsPage({
    super.key,
    this.onSettingsChanged,
    this.isVpnConnected = false,
    this.onReconnectRequest,
  });

  @override
  State<ImprovedRoutingSettingsPage> createState() =>
      _ImprovedRoutingSettingsPageState();
}

class _ImprovedRoutingSettingsPageState
    extends State<ImprovedRoutingSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;

  List<String> _directDomains = [];
  List<String> _blockedDomains = [];
  List<String> _proxyDomains = [];
  List<String> _directIps = [];

  final _directDomainCtrl = TextEditingController();
  final _blockedDomainCtrl = TextEditingController();
  final _proxyDomainCtrl = TextEditingController();
  final _directIpCtrl = TextEditingController();

  final Map<String, List<String>> _domainPresets = {
    'Россия': ['ru', 'рф', 'su', 'yandex.ru', 'vk.com', 'mail.ru', 'ok.ru', 'avito.ru', 'ozon.ru'],
    'Соц. сети (РФ)': ['vk.com', 'ok.ru', 'dzen.ru', 'rutube.ru'],
    'Стриминг (РФ)': ['kinopoisk.ru', 'ivi.ru', 'more.tv', 'premier.one'],
    'Google сервисы': ['google.com', 'gmail.com', 'youtube.com', 'googlevideo.com', 'gstatic.com'],
    'Microsoft': ['microsoft.com', 'office.com', 'live.com', 'outlook.com', 'msn.com'],
    'Соц. сети (Запад)': ['facebook.com', 'instagram.com', 'twitter.com', 'x.com', 'tiktok.com'],
  };

  final Map<String, List<String>> _blockedPresets = {
    'Реклама': ['ads.', 'analytics.', 'doubleclick.net', 'google-analytics.com', 'googleadservices.com'],
    'Трекеры': ['facebook.com/tr', 'pixel.', 'tracking.', 'tracker.'],
    'Телеметрия': ['telemetry.', 'metrics.', 'crash-reporting.'],
  };

  final Map<String, List<String>> _ipPresets = {
    'Локальные сети': ['192.168.0.0/16', '10.0.0.0/8', '172.16.0.0/12', '127.0.0.0/8'],
    'Localhost': ['127.0.0.1/32', '::1/128'],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _directDomainCtrl.dispose();
    _blockedDomainCtrl.dispose();
    _proxyDomainCtrl.dispose();
    _directIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _directDomains = _parseToList(settings.directDomains);
        _blockedDomains = _parseToList(settings.blockedDomains);
        _proxyDomains = _parseToList(settings.proxyDomains);
        _directIps = _parseToList(settings.directIps);
        _isLoading = false;
      });
    }
  }

  List<String> _parseToList(String input) =>
      input.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String _listToString(List<String> list) => list.join(', ');

  Future<void> _saveSettings() async {
    final currentSettings = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort: currentSettings.localPort,
      directDomains: _listToString(_directDomains),
      blockedDomains: _listToString(_blockedDomains),
      directIps: _listToString(_directIps),
      proxyDomains: _listToString(_proxyDomains),
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
        message: 'Правила маршрутизации сохранены',
        type: NotificationType.success,
      );
    }
  }

  void _addDomain(
      List<String> list, TextEditingController controller, String name) {
    final value = controller.text.trim();
    if (value.isEmpty) {
      CustomNotification.show(context,
          message: 'Введите $name', type: NotificationType.error);
      return;
    }
    if (!_isValidDomainOrIp(value)) {
      CustomNotification.show(context,
          message: 'Некорректный формат: $value',
          type: NotificationType.error);
      return;
    }
    setState(() {
      if (!list.contains(value)) {
        list.add(value);
        controller.clear();
      }
    });
  }

  bool _isValidDomainOrIp(String value) {
    if (value.contains(' ')) return false;
    if (value.startsWith('domain:') ||
        value.startsWith('full:') ||
        value.startsWith('regexp:') ||
        value.startsWith('geosite:')) return true;
    if (value.contains('/'))
      return RegExp(r'^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$').hasMatch(value);
    if (RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(value)) return true;
    if (!value.contains('.') &&
        RegExp(r'^[a-zA-Zа-яА-Я0-9]+$').hasMatch(value)) return true;
    if (value.startsWith('.'))
      return RegExp(r'^\.[a-zA-Z0-9а-яА-Я\-]+(\.[a-zA-Z0-9а-яА-Я\-]+)*$')
          .hasMatch(value);
    return RegExp(r'^([a-zA-Z0-9а-яА-Я\-]+\.)*[a-zA-Z0-9а-яА-Я\-]+$')
        .hasMatch(value);
  }

  void _removeDomain(List<String> list, String value) =>
      setState(() => list.remove(value));

  void _addPreset(List<String> targetList, List<String> preset) {
    setState(() {
      for (var item in preset) {
        if (!targetList.contains(item)) targetList.add(item);
      }
    });
    CustomNotification.show(context,
        message: 'Пресет добавлен', type: NotificationType.success);
  }

  void _showPresetDialog(BuildContext context, String title,
      Map<String, List<String>> presets, List<String> targetList) {
    final themeManager = ThemeManager();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0E27),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: presets.entries.map((entry) {
              return Card(
                color: themeManager.settings.accentColor.withOpacity(0.3),
                child: ListTile(
                  title: Text(entry.key,
                      style:
                      const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    entry.value.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.add_circle,
                        color: themeManager.settings.primaryColor),
                    onPressed: () {
                      _addPreset(targetList, entry.value);
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Widget _buildChipSection({
    required String title,
    required String subtitle,
    required List<String> items,
    required TextEditingController controller,
    required String placeholder,
    required VoidCallback onAdd,
    Map<String, List<String>>? presets,
    IconData icon = Icons.add,
  }) {
    final themeManager = ThemeManager();
    return Card(
      color: themeManager.settings.accentColor.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: themeManager.settings.primaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: themeManager.settings.primaryColor)),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (presets != null)
                  IconButton(
                    icon: const Icon(Icons.library_add, size: 20),
                    tooltip: 'Пресеты',
                    onPressed: () => _showPresetDialog(
                        context, 'Выберите пресет', presets, items),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, size: 20),
                  tooltip: 'Очистить всё',
                  onPressed: items.isEmpty
                      ? null
                      : () => setState(() => items.clear()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: placeholder,
                      hintStyle:
                      TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      prefixIcon: const Icon(Icons.edit, size: 18),
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.add_circle,
                      color: themeManager.settings.primaryColor, size: 32),
                  onPressed: onAdd,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Нет элементов',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3))),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((item) {
                  return Chip(
                    label: Text(item,
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor:
                    themeManager.settings.primaryColor.withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeDomain(items, item),
                    deleteIconColor: Colors.white70,
                  );
                }).toList(),
              ),
            const SizedBox(height: 8),
            Text('Всего: ${items.length}',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: themeManager.settings.accentColor.withOpacity(0.9),
        title: const Text('Маршрутизация'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: themeManager.settings.primaryColor,
          indicatorWeight: 3,
          labelColor: themeManager.settings.primaryColor,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.public, size: 18), text: 'Домены и IP'),
            Tab(icon: Icon(Icons.apps, size: 18), text: 'Приложения'),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Фон
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
                          1.0 - themeManager.settings.backgroundOpacity),
                    ),
                  ),
                ],
              ),
            ),

          TabBarView(
            controller: _tabController,
            children: [
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.blue, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Добавляйте домены и IP-адреса для гибкой маршрутизации трафика',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue[200]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildChipSection(
                    title: 'Прямое подключение (Direct)',
                    subtitle: 'Домены, которые будут открываться без VPN',
                    items: _directDomains,
                    controller: _directDomainCtrl,
                    placeholder: 'Например: yandex.ru или ru',
                    icon: Icons.public,
                    presets: _domainPresets,
                    onAdd: () => _addDomain(_directDomains, _directDomainCtrl, 'домен'),
                  ),
                  const SizedBox(height: 16),
                  _buildChipSection(
                    title: 'Принудительно через VPN (Proxy)',
                    subtitle: 'Домены, которые всегда будут идти через VPN',
                    items: _proxyDomains,
                    controller: _proxyDomainCtrl,
                    placeholder: 'Например: google.com',
                    icon: Icons.vpn_lock,
                    presets: _domainPresets,
                    onAdd: () => _addDomain(_proxyDomains, _proxyDomainCtrl, 'домен'),
                  ),
                  const SizedBox(height: 16),
                  _buildChipSection(
                    title: 'Заблокированные (Block)',
                    subtitle: 'Домены, к которым будет запрещен доступ',
                    items: _blockedDomains,
                    controller: _blockedDomainCtrl,
                    placeholder: 'Например: ads.example.com',
                    icon: Icons.block,
                    presets: _blockedPresets,
                    onAdd: () => _addDomain(_blockedDomains, _blockedDomainCtrl, 'домен'),
                  ),
                  const SizedBox(height: 16),
                  _buildChipSection(
                    title: 'IP адреса (Direct)',
                    subtitle: 'IP адреса или подсети для прямого подключения',
                    items: _directIps,
                    controller: _directIpCtrl,
                    placeholder: 'Например: 192.168.0.0/16',
                    icon: Icons.router,
                    presets: _ipPresets,
                    onAdd: () => _addDomain(_directIps, _directIpCtrl, 'IP адрес'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeManager.settings.primaryColor,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save, size: 24),
                          SizedBox(width: 12),
                          Text('Сохранить настройки'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),

              // ── Вкладка 2 ──────────────────────────────────
              AppRoutingPage(
                isVpnConnected: widget.isVpnConnected,
                onReconnectRequest: widget.onReconnectRequest,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0E27),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 12),
            Text('Справка маршрутизации'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Прямое подключение (Direct)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                  'Домены открываются напрямую без VPN.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('Принудительно через VPN (Proxy)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                  'Домены всегда идут через VPN, независимо от других правил.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('Заблокированные (Block)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Полностью запрещённый доступ к домену.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('Приложения (только TUN-режим)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                  'Выбранные приложения будут маршрутизироваться через VPN по имени процесса.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              const Text('Форматы записей:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text(
                  '• TLD: ru, com, net\n'
                      '• Домен: google.com, yandex.ru\n'
                      '• Поддомены: .google.com\n'
                      '• IP: 192.168.1.1\n'
                      '• CIDR: 192.168.0.0/16\n'
                      '• Точное: full:example.com\n'
                      '• Regex: regexp:.*\\.ads\\..*',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                  Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Для зоны "ru" вводите просто ru. '
                            'Для всех поддоменов Google — .google.com',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange[200]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно')),
        ],
      ),
    );
  }
}