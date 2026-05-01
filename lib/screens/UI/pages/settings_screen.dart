import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/services/autostart_service.dart';
import 'package:keqdis/services/debug_log_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/localization/app_localization.dart';
import 'package:keqdis/screens/UI/widgets/app_design_layer.dart';
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
  final _dnsCtrl = TextEditingController();
  String _languageCode = 'ru';
  bool _useCustomDns = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = SettingsStorage.loadSettings().then((s) {
      if (mounted) {
        _portCtrl.text = s.localPort.toString();
        _dnsCtrl.text = s.customDnsServers;
        _useCustomDns = s.useCustomDns;
      }
      _languageCode = s.appLanguage;
      return s;
    });
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _dnsCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePort() async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(
      AppSettings(
        localPort: int.tryParse(_portCtrl.text) ?? 2080,
        useCustomDns: _useCustomDns,
        customDnsServers: _dnsCtrl.text.trim(),
        directDomains: cur.directDomains,
        blockedDomains: cur.blockedDomains,
        directIps: cur.directIps,
        proxyDomains: cur.proxyDomains,
        pingType: cur.pingType,
        autoStart: cur.autoStart,
        minimizeToTray: cur.minimizeToTray,
        startMinimized: cur.startMinimized,
        autoConnectLastServer: cur.autoConnectLastServer,
        lastVpnMode: cur.lastVpnMode,
        appLanguage: cur.appLanguage,
        debugMode: cur.debugMode,
        shareDeviceHwid: cur.shareDeviceHwid,
        deviceHwid: cur.deviceHwid,
      ),
    );
    widget.onSettingsChanged?.call();
    CustomNotification.show(
      context,
      message: context.tr('local_port_saved'),
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final s = themeManager.settings;

    return FutureBuilder<AppSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: s.primaryColor),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Основные настройки ─────────────────────────────────────────
            AppSectionTitle(text: context.tr('main_settings')),
            const SizedBox(height: 12),

            _SettingsCard(
              settings: s,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('local_port'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: s.textColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ThemedTextField(
                            controller: _portCtrl,
                            hint: context.tr('local_port_hint'),
                            settings: s,
                            inputType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _savePort,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: s.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            minimumSize: const Size(110, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            context.tr('save'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.tr('use_custom_dns'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: s.textColor,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        context.tr('use_custom_dns_subtitle'),
                        style: TextStyle(
                          fontSize: 11,
                          color: s.secondaryTextColor,
                        ),
                      ),
                      value: _useCustomDns,
                      onChanged: (v) => setState(() => _useCustomDns = v),
                      activeColor: s.primaryColor,
                    ),
                    if (_useCustomDns) ...[
                      const SizedBox(height: 8),
                      _ThemedTextField(
                        controller: _dnsCtrl,
                        hint: context.tr('custom_dns_hint'),
                        settings: s,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Дополнительные настройки ───────────────────────────────────
            AppSectionTitle(text: context.tr('advanced_settings')),
            const SizedBox(height: 12),

            _MenuCard(
              title: context.tr('app_behavior'),
              subtitle: context.tr('app_behavior_subtitle'),
              icon: Icons.settings_applications_rounded,
              settings: s,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BehaviorSettingsPage(
                    onSettingsChanged: widget.onSettingsChanged,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            _MenuCard(
              title: context.tr('routing'),
              subtitle: context.tr('routing_subtitle'),
              icon: Icons.route_rounded,
              settings: s,
              onTap: () {
                final vpn = context.read<VpnController>();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImprovedRoutingSettingsPage(
                      onSettingsChanged: widget.onSettingsChanged,
                      isVpnConnected: vpn.isConnected,
                      onReconnectRequest: () async {
                        await vpn.disconnect();
                        await vpn.connect();
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),

            _MenuCard(
              title: context.tr('ping_settings'),
              subtitle: context.tr('ping_settings_subtitle'),
              icon: Icons.speed_rounded,
              settings: s,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PingSettingsPage(
                    onSettingsChanged: widget.onSettingsChanged,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Внешний вид ────────────────────────────────────────────────
            AppSectionTitle(text: context.tr('appearance')),
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
                        // Цветовые пресеты
                        Row(
                          children: [
                            Icon(
                              Icons.palette_rounded,
                              color: s.primaryColor,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('color_theme_title'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: s.textColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    context.tr('color_theme_hint'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: s.secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset in themeManager.presets)
                              ChoiceChip(
                                label: Text(preset.name),
                                selected: s.presetId == preset.id,
                                onSelected: (_) async {
                                  await themeManager.applyPreset(preset.id);
                                  widget.onThemeChanged?.call();
                                },
                                selectedColor: s.primaryColor.withOpacity(0.2),
                                side: BorderSide(
                                  color: s.presetId == preset.id
                                      ? s.primaryColor.withOpacity(0.5)
                                      : s.borderColor,
                                ),
                                labelStyle: TextStyle(
                                  color: s.textColor,
                                  fontWeight: s.presetId == preset.id
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                backgroundColor: s.searchBarColor,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(
                              Icons.language_rounded,
                              color: s.primaryColor,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('language'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: s.textColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    context.tr('change_language'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: s.secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                value: _languageCode,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: s.searchBarColor,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: s.borderColor,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                      color: s.borderColor,
                                    ),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'ru',
                                    child: Text(context.tr('russian')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'en',
                                    child: Text(context.tr('english')),
                                  ),
                                ],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  setState(() => _languageCode = v);
                                  await AppLocalization().setLanguage(v);
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                          ],
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
  bool _autoStart = false;
  bool _minimizeToTray = true;
  bool _startMinimized = false;
  bool _autoConnectLastServer = false;
  bool _shareDeviceHwid = true;
  bool _debugMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _autoStart = s.autoStart;
        _minimizeToTray = s.minimizeToTray;
        _startMinimized = s.startMinimized;
        _autoConnectLastServer = s.autoConnectLastServer;
        _shareDeviceHwid = s.shareDeviceHwid;
        _debugMode = s.debugMode;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(
      AppSettings(
        localPort: cur.localPort,
        useCustomDns: cur.useCustomDns,
        customDnsServers: cur.customDnsServers,
        directDomains: cur.directDomains,
        blockedDomains: cur.blockedDomains,
        directIps: cur.directIps,
        proxyDomains: cur.proxyDomains,
        pingType: cur.pingType,
        autoStart: _autoStart,
        minimizeToTray: _minimizeToTray,
        startMinimized: _startMinimized,
        autoConnectLastServer: _autoConnectLastServer,
        shareDeviceHwid: _shareDeviceHwid,
        deviceHwid: cur.deviceHwid,
        lastVpnMode: cur.lastVpnMode,
        appLanguage: cur.appLanguage,
        debugMode: _debugMode,
      ),
    );
    try {
      await AutoStartService.toggle(_autoStart);
    } catch (e) {
      if (!mounted) return;
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('behavior_autostart_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
      return;
    }
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return _SubPage(
      title: context.tr('behavior_page_title'),
      settings: s,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: s.primaryColor))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SwitchCard(
                  title: context.tr('autostart'),
                  subtitle: context.tr('behavior_autostart_subtitle'),
                  value: _autoStart,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _autoStart = v);
                    _save();
                  },
                ),
                const SizedBox(height: 10),
                _SwitchCard(
                  title: context.tr('minimize_to_tray'),
                  subtitle: context.tr('behavior_minimize_to_tray_subtitle'),
                  value: _minimizeToTray,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _minimizeToTray = v);
                    _save();
                  },
                ),
                const SizedBox(height: 10),
                _SwitchCard(
                  title: context.tr('start_minimized'),
                  subtitle: context.tr('behavior_start_minimized_subtitle'),
                  value: _startMinimized,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _startMinimized = v);
                    _save();
                  },
                ),
                const SizedBox(height: 10),
                _SwitchCard(
                  title: context.tr('autoconnect'),
                  subtitle: context.tr('behavior_autoconnect_subtitle'),
                  value: _autoConnectLastServer,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _autoConnectLastServer = v);
                    _save();
                  },
                ),
                const SizedBox(height: 10),
                _SwitchCard(
                  title: context.tr('share_device_hwid'),
                  subtitle: context.tr('share_device_hwid_subtitle'),
                  value: _shareDeviceHwid,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _shareDeviceHwid = v);
                    _save();
                  },
                ),
                const SizedBox(height: 10),
                _SwitchCard(
                  title: context.tr('debug_mode'),
                  subtitle: context.tr('debug_mode_subtitle'),
                  value: _debugMode,
                  settings: s,
                  onChanged: (v) {
                    setState(() => _debugMode = v);
                    _save();
                  },
                ),
                if (_debugMode) ...[
                  const SizedBox(height: 10),
                  _SettingsCard(
                    settings: s,
                    child: ListTile(
                      leading: Icon(
                        Icons.bug_report_rounded,
                        color: s.primaryColor,
                      ),
                      title: Text(
                        context.tr('open_debug_logs'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: s.textColor,
                        ),
                      ),
                      subtitle: Text(
                        context.tr('open_debug_logs_subtitle'),
                        style: TextStyle(
                          color: s.secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: s.secondaryTextColor,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DebugLogsPage(),
                        ),
                      ),
                    ),
                  ),
                ],
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsStorage.loadSettings();
    if (mounted)
      setState(() {
        _pingType = s.pingType;
        _isLoading = false;
      });
  }

  Future<void> _save(String t) async {
    final cur = await SettingsStorage.loadSettings();
    await SettingsStorage.saveSettings(
      AppSettings(
        localPort: cur.localPort,
        useCustomDns: cur.useCustomDns,
        customDnsServers: cur.customDnsServers,
        directDomains: cur.directDomains,
        blockedDomains: cur.blockedDomains,
        directIps: cur.directIps,
        proxyDomains: cur.proxyDomains,
        pingType: t,
        autoStart: cur.autoStart,
        minimizeToTray: cur.minimizeToTray,
        startMinimized: cur.startMinimized,
        autoConnectLastServer: cur.autoConnectLastServer,
        lastVpnMode: cur.lastVpnMode,
        appLanguage: cur.appLanguage,
        debugMode: cur.debugMode,
        shareDeviceHwid: cur.shareDeviceHwid,
        deviceHwid: cur.deviceHwid,
      ),
    );
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return _SubPage(
      title: context.tr('ping_settings'),
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
                        title: Text(
                          context.tr('ping_tcp'),
                          style: TextStyle(
                            color: s.textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          context.tr('ping_tcp_description'),
                          style: TextStyle(
                            color: s.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        value: 'tcp',
                        groupValue: _pingType,
                        activeColor: s.primaryColor,
                        onChanged: (v) {
                          setState(() => _pingType = v!);
                          _save(v!);
                        },
                      ),
                      Divider(height: 1, color: s.borderColor),
                      RadioListTile<String>(
                        title: Text(
                          context.tr('ping_proxy'),
                          style: TextStyle(
                            color: s.textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          context.tr('ping_proxy_description'),
                          style: TextStyle(
                            color: s.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        value: 'proxy',
                        groupValue: _pingType,
                        activeColor: s.primaryColor,
                        onChanged: (v) {
                          setState(() => _pingType = v!);
                          _save(v!);
                        },
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

  const _SubPage({
    required this.title,
    required this.settings,
    required this.child,
  });

  Color _appBarBg(ThemeSettings s, bool hasCustomBackground) {
    if (!hasCustomBackground) return s.cardColor;
    // Make app bars solid even with wallpaper.
    return const Color(0xFFF5E6EA);
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Scaffold(
      backgroundColor: s.backgroundColor,
      appBar: AppBar(
        backgroundColor: _appBarBg(s, false),
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: TextStyle(color: s.textColor)),
        iconTheme: IconThemeData(color: s.textColor),
      ),
      body: child,
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final ThemeSettings settings;
  final Widget child;
  const _SettingsCard({required this.settings, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: settings.cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: settings.borderColor),
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hovered ? s.primaryColor.withOpacity(0.08) : s.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? s.primaryColor.withOpacity(0.4) : s.borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: s.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: s.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: s.textColor,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: s.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: s.secondaryTextColor,
              ),
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
        color: s.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.borderColor),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: s.textColor,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: s.secondaryTextColor),
        ),
        value: value,
        onChanged: onChanged,
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
      controller: controller,
      keyboardType: inputType,
      style: TextStyle(fontSize: 14, color: s.textColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: s.secondaryTextColor.withOpacity(0.5)),
        filled: true,
        fillColor: s.searchBarColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}

class DebugLogsPage extends StatelessWidget {
  const DebugLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    final logs = DebugLogService();

    return _SubPage(
      title: context.tr('debug_logs_title'),
      settings: s,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: logs.clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(context.tr('clear_logs')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final text = logs.entries.join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!context.mounted) return;
                      CustomNotification.show(
                        context,
                        message: context.tr('logs_copied'),
                        type: NotificationType.success,
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(context.tr('copy_logs')),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: logs,
              builder: (context, _) {
                final entries = logs.entries;
                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      context.tr('debug_logs_empty'),
                      style: TextStyle(color: s.secondaryTextColor),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final line = entries[entries.length - 1 - index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: s.cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: s.borderColor),
                      ),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          color: s.textColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
