import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/services/autostart_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/screens/UI/controller/vpn_controller.dart';
import 'improved_routing_settings.dart';

// ─── Главный экран настроек ───────────────────────────────────────────────────
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
      if (mounted) _portCtrl.text = s.localPort.toString();
      return s;
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePort() async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(AppSettings(
      localPort:            int.tryParse(_portCtrl.text) ?? 2080,
      directDomains:        cur.directDomains,
      blockedDomains:       cur.blockedDomains,
      directIps:            cur.directIps,
      proxyDomains:         cur.proxyDomains,
      pingType:             cur.pingType,
      autoStart:            cur.autoStart,
      minimizeToTray:       cur.minimizeToTray,
      startMinimized:       cur.startMinimized,
      autoConnectLastServer: cur.autoConnectLastServer,
    ));
    widget.onSettingsChanged?.call();
    CustomNotification.show(
      context,
      message: 'Локальный порт сохранён. Переподключитесь для применения.',
      type:    NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final s            = themeManager.settings;

    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: s.primaryColor));
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Основные настройки ─────────────────────────────────────────
            _SectionTitle(label: 'Основные настройки', settings: s),
            const SizedBox(height: 12),

            _SettingsCard(
              settings: s,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Локальный порт',
                        style: TextStyle(fontWeight: FontWeight.w600, color: s.textColor, fontSize: 14)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ThemedTextField(
                            controller:  _portCtrl,
                            hint:        'Например: 2080',
                            settings:    s,
                            inputType:   TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _savePort,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: s.primaryColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                          child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Дополнительные настройки ───────────────────────────────────
            _SectionTitle(label: 'Дополнительные настройки', settings: s),
            const SizedBox(height: 12),

            _MenuCard(
              title:    'Поведение приложения',
              subtitle: 'Автозапуск, свертывание в трей и другое',
              icon:     Icons.settings_applications_rounded,
              settings: s,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BehaviorSettingsPage(onSettingsChanged: widget.onSettingsChanged),
              )),
            ),
            const SizedBox(height: 10),

            _MenuCard(
              title:    'Маршрутизация',
              subtitle: 'Правила для доменов, IP-адресов и блокировки',
              icon:     Icons.route_rounded,
              settings: s,
              onTap: () {
                final vpn = context.read<VpnController>();
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImprovedRoutingSettingsPage(
                    onSettingsChanged:  widget.onSettingsChanged,
                    isVpnConnected:     vpn.isConnected,
                    onReconnectRequest: () async {
                      await vpn.disconnect();
                      await vpn.connect();
                    },
                  ),
                ));
              },
            ),
            const SizedBox(height: 10),

            _MenuCard(
              title:    'Настройки пинга',
              subtitle: 'Выбор типа пинга (TCP или через прокси)',
              icon:     Icons.speed_rounded,
              settings: s,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PingSettingsPage(onSettingsChanged: widget.onSettingsChanged),
              )),
            ),

            const SizedBox(height: 28),

            // ── Внешний вид ────────────────────────────────────────────────
            _SectionTitle(label: 'Внешний вид', settings: s),
            const SizedBox(height: 12),

            AnimatedBuilder(
              animation: themeManager,
              builder: (context, _) {
                return _SettingsCard(
                  settings: s,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Переключатель тёмной темы
                        Row(
                          children: [
                            Icon(
                              s.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                              color: s.primaryColor,
                              size:  22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Тёмная тема',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: s.textColor, fontSize: 14)),
                                  Text('Переключить между светлой и тёмной темой',
                                      style: TextStyle(fontSize: 11, color: s.secondaryTextColor)),
                                ],
                              ),
                            ),
                            Switch(
                              value:       s.isDarkMode,
                              onChanged:   (v) async {
                                await themeManager.setDarkMode(v);
                                widget.onThemeChanged?.call();
                              },
                              activeColor: s.primaryColor,
                            ),
                          ],
                        ),

                        if (themeManager.hasCustomBackground) ...[
                          Divider(height: 24, color: s.borderColor),
                          // Превью фона
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        File(themeManager.settings.backgroundImagePath!),
                                        fit: BoxFit.cover,
                                        alignment: Alignment.center,
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: IconButton(
                                          icon: const Icon(Icons.close, color: Colors.white),
                                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                          onPressed: () async {
                                            await themeManager.removeBackground();
                                            widget.onThemeChanged?.call();
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text('Прозрачность фона',
                              style: TextStyle(color: s.secondaryTextColor, fontSize: 13)),
                          Slider(
                            value:         themeManager.settings.backgroundOpacity,
                            min:           0.1,
                            max:           1.0,
                            divisions:     20,
                            label:         '${(themeManager.settings.backgroundOpacity * 100).round()}%',
                            activeColor:   s.primaryColor,
                            inactiveColor: s.borderColor,
                            onChanged:     (v) => themeManager.updateOpacity(v),
                            onChangeEnd:   (_) => themeManager.saveTheme(),
                          ),
                          Text('Размытие фона',
                              style: TextStyle(color: s.secondaryTextColor, fontSize: 13)),
                          Slider(
                            value:         themeManager.settings.blurIntensity,
                            min:           0,
                            max:           20,
                            divisions:     40,
                            label:         themeManager.settings.blurIntensity.round().toString(),
                            activeColor:   s.primaryColor,
                            inactiveColor: s.borderColor,
                            onChanged:     (v) => themeManager.updateBlur(v),
                            onChangeEnd:   (_) => themeManager.saveTheme(),
                          ),
                          Divider(height: 16, color: s.borderColor),
                        ],

                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await themeManager.pickBackgroundImage();
                              widget.onThemeChanged?.call();
                            },
                            icon:  const Icon(Icons.image_rounded),
                            label: Text(themeManager.hasCustomBackground
                                ? 'Изменить фон'
                                : 'Выбрать фоновое изображение'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: s.primaryColor,
                              side: BorderSide(color: s.primaryColor.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Цвета интерфейса автоматически адаптируются под выбранное изображение',
                          style: TextStyle(fontSize: 11, color: s.secondaryTextColor.withOpacity(0.6)),
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

// ─── BehaviorSettingsPage ─────────────────────────────────────────────────────
class BehaviorSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const BehaviorSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  bool _autoStart            = false;
  bool _minimizeToTray       = true;
  bool _startMinimized       = false;
  bool _autoConnectLastServer = false;
  bool _isLoading            = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _autoStart             = s.autoStart;
        _minimizeToTray        = s.minimizeToTray;
        _startMinimized        = s.startMinimized;
        _autoConnectLastServer  = s.autoConnectLastServer;
        _isLoading             = false;
      });
    }
  }

  Future<void> _save() async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(AppSettings(
      localPort:             cur.localPort,
      directDomains:         cur.directDomains,
      blockedDomains:        cur.blockedDomains,
      directIps:             cur.directIps,
      proxyDomains:          cur.proxyDomains,
      pingType:              cur.pingType,
      autoStart:             _autoStart,
      minimizeToTray:        _minimizeToTray,
      startMinimized:        _startMinimized,
      autoConnectLastServer: _autoConnectLastServer,
    ));
    await AutoStartService.toggle(_autoStart);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return _SubPage(
      title:   'Поведение приложения',
      settings: s,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: s.primaryColor))
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SwitchCard(
            title:    'Автозапуск при старте',
            subtitle: 'Запускать вместе с системой',
            value:    _autoStart,
            settings: s,
            onChanged: (v) { setState(() => _autoStart = v); _save(); },
          ),
          const SizedBox(height: 10),
          _SwitchCard(
            title:    'Сворачивать в трей',
            subtitle: 'При закрытии окна сворачивать в системный трей',
            value:    _minimizeToTray,
            settings: s,
            onChanged: (v) { setState(() => _minimizeToTray = v); _save(); },
          ),
          const SizedBox(height: 10),
          _SwitchCard(
            title:    'Запускать свёрнутым',
            subtitle: 'Сразу сворачиваться в трей при автозапуске',
            value:    _startMinimized,
            settings: s,
            onChanged: (v) { setState(() => _startMinimized = v); _save(); },
          ),
          const SizedBox(height: 10),
          _SwitchCard(
            title:    'Автоподключение',
            subtitle: 'Подключаться к последнему серверу при старте',
            value:    _autoConnectLastServer,
            settings: s,
            onChanged: (v) { setState(() => _autoConnectLastServer = v); _save(); },
          ),
        ],
      ),
    );
  }
}

// ─── PingSettingsPage ─────────────────────────────────────────────────────────
class PingSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const PingSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<PingSettingsPage> createState() => _PingSettingsPageState();
}

class _PingSettingsPageState extends State<PingSettingsPage> {
  String _pingType = 'tcp';
  bool   _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsStorage.loadSettings();
    if (mounted) setState(() { _pingType = s.pingType; _isLoading = false; });
  }

  Future<void> _save(String t) async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(AppSettings(
      localPort:             cur.localPort,
      directDomains:         cur.directDomains,
      blockedDomains:        cur.blockedDomains,
      directIps:             cur.directIps,
      proxyDomains:          cur.proxyDomains,
      pingType:              t,
      autoStart:             cur.autoStart,
      minimizeToTray:        cur.minimizeToTray,
      startMinimized:        cur.startMinimized,
      autoConnectLastServer: cur.autoConnectLastServer,
    ));
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return _SubPage(
      title:    'Настройки пинга',
      settings: s,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: s.primaryColor))
          : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SettingsCard(
            settings: s,
            child: Column(
              children: [
                RadioListTile<String>(
                  title:    Text('TCP пинг', style: TextStyle(color: s.textColor, fontWeight: FontWeight.w500)),
                  subtitle: Text('Прямое подключение к серверу',
                      style: TextStyle(color: s.secondaryTextColor, fontSize: 12)),
                  value:       'tcp',
                  groupValue:  _pingType,
                  activeColor: s.primaryColor,
                  onChanged: (v) { setState(() => _pingType = v!); _save(v!); },
                ),
                Divider(height: 1, color: s.borderColor),
                RadioListTile<String>(
                  title:    Text('Пинг через прокси', style: TextStyle(color: s.textColor, fontWeight: FontWeight.w500)),
                  subtitle: Text('Проверка через локальный прокси',
                      style: TextStyle(color: s.secondaryTextColor, fontSize: 12)),
                  value:       'proxy',
                  groupValue:  _pingType,
                  activeColor: s.primaryColor,
                  onChanged: (v) { setState(() => _pingType = v!); _save(v!); },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Вспомогательные виджеты ──────────────────────────────────────────────────
class _SubPage extends StatelessWidget {
  final String title;
  final ThemeSettings settings;
  final Widget child;

  const _SubPage({required this.title, required this.settings, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final themeManager = ThemeManager();
    return Scaffold(
      backgroundColor: themeManager.hasCustomBackground ? Colors.transparent : s.backgroundColor,
      appBar: AppBar(
        title: Text(title),
      ),
      body: themeManager.hasCustomBackground
          ? Stack(
              children: [
                const Positioned.fill(child: _GlassBackground()),
                child,
              ],
            )
          : child,
    );
  }
}

class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    final tm = ThemeManager();
    final s = tm.settings;
    final path = s.backgroundImagePath;
    if (path == null) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final provider = ResizeImage(
      FileImage(File(path)),
      width: (mq.size.width * mq.devicePixelRatio).round(),
      height: (mq.size.height * mq.devicePixelRatio).round(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: provider,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            Future.microtask(() => tm.removeBackground());
            return Container(color: s.backgroundColor);
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: s.blurIntensity,
            sigmaY: s.blurIntensity,
          ),
          child: Container(
            color: Colors.black.withAlpha(
              ((1.0 - s.backgroundOpacity) * 255).round().clamp(0, 255),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final ThemeSettings settings;
  const _SectionTitle({required this.label, required this.settings});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize:   18,
      fontWeight: FontWeight.w700,
      color:      settings.textColor,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  final ThemeSettings settings;
  final Widget child;
  const _SettingsCard({required this.settings, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:        settings.cardColor,
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: settings.borderColor),
    ),
    child: child,
  );
}

class _MenuCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final ThemeSettings settings;
  final VoidCallback onTap;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.settings,
    required this.onTap,
  });

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:  const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        _hovered ? s.primaryColor.withOpacity(0.08) : s.cardColor,
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(
              color: _hovered ? s.primaryColor.withOpacity(0.4) : s.borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding:    const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color:        s.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: s.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: TextStyle(fontWeight: FontWeight.w600, color: s.textColor, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        style: TextStyle(fontSize: 12, color: s.secondaryTextColor)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: s.secondaryTextColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ThemeSettings settings;
  final Function(bool) onChanged;

  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Container(
      decoration: BoxDecoration(
        color:        s.cardColor,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: s.borderColor),
      ),
      child: SwitchListTile(
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: s.textColor, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: s.secondaryTextColor)),
        value:       value,
        onChanged:   onChanged,
        activeColor: s.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ThemeSettings settings;
  final TextInputType inputType;

  const _ThemedTextField({
    required this.controller,
    required this.hint,
    required this.settings,
    this.inputType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return TextField(
      controller:  controller,
      keyboardType: inputType,
      style: TextStyle(fontSize: 14, color: s.textColor),
      decoration: InputDecoration(
        hintText:  hint,
        hintStyle: TextStyle(color: s.secondaryTextColor.withOpacity(0.5)),
        filled:    true,
        fillColor: s.searchBarColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:   BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}
