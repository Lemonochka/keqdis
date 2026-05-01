import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/storages/improved_settings_storage.dart';
import 'package:keqdis/services/autostart_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/localization/app_localization.dart';

// Отдельный файл BehaviorSettingsPage (если используется отдельно от settings_screen.dart)
class BehaviorSettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const BehaviorSettingsPage({super.key, this.onSettingsChanged});

  @override
  State<BehaviorSettingsPage> createState() => _BehaviorSettingsPageState();
}

class _BehaviorSettingsPageState extends State<BehaviorSettingsPage> {
  bool _autoStart             = false;
  bool _minimizeToTray        = true;
  bool _startMinimized        = false;
  bool _autoConnectLastServer = false;
  bool _shareDeviceHwid       = true;
  bool _isLoading             = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsStorage.loadSettings();
    if (mounted) {
      setState(() {
        _autoStart             = settings.autoStart;
        _minimizeToTray        = settings.minimizeToTray;
        _startMinimized        = settings.startMinimized;
        _autoConnectLastServer = settings.autoConnectLastServer;
        _shareDeviceHwid       = settings.shareDeviceHwid;
        _isLoading             = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final cur = await SettingsStorage.loadSettings();
    final settings = AppSettings(
      localPort:             cur.localPort,
      useCustomDns:         cur.useCustomDns,
      customDnsServers:     cur.customDnsServers,
      directDomains:         cur.directDomains,
      blockedDomains:        cur.blockedDomains,
      directIps:             cur.directIps,
      proxyDomains:          cur.proxyDomains,
      pingType:              cur.pingType,
      lastVpnMode:           cur.lastVpnMode,
      autoStart:             _autoStart,
      minimizeToTray:        _minimizeToTray,
      startMinimized:        _startMinimized,
      autoConnectLastServer: _autoConnectLastServer,
      shareDeviceHwid:       _shareDeviceHwid,
      deviceHwid:            cur.deviceHwid,
      appLanguage:           cur.appLanguage,
      debugMode:             cur.debugMode,
    );

    await SettingsStorage.saveSettings(settings);

    try {
      await AutoStartService.toggle(_autoStart);
    } catch (e) {
      debugPrint('Failed to toggle autostart: $e');
      if (mounted) {
        CustomNotification.show(
          context,
          message: AppLocalization().t('behavior_autostart_error').replaceFirst('{error}', '$e'),
          type:    NotificationType.error,
        );
        return;
      }
    }

    widget.onSettingsChanged?.call();

    if (mounted) {
      CustomNotification.show(
        context,
        message: AppLocalization().t('behavior_saved'),
        type:    NotificationType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return Scaffold(
      backgroundColor: s.backgroundColor,
      body: Stack(
        children: [
          // Кастомный фон
          if (ThemeManager().hasCustomBackground)
            Positioned.fill(child: _buildBackground(context, s)),

          Column(
            children: [
              AppBar(
                backgroundColor:  s.isGlassmorphism
                    ? (s.isDark ? const Color(0xFF141010) : const Color(0xFFF5E6EA))
                    : s.sidebarColor,
                foregroundColor:  s.textColor,
                elevation:        0,
                surfaceTintColor: Colors.transparent,
                iconTheme:        IconThemeData(color: s.primaryColor),
                title: Text(
                  context.tr('behavior_page_title'),
                  style: TextStyle(
                    color:      s.textColor,
                    fontWeight: FontWeight.w600,
                    fontSize:   17,
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: s.primaryColor))
                    : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _SwitchCard(
                      title:    context.tr('autostart'),
                      subtitle: context.tr('behavior_autostart_subtitle'),
                      value:    _autoStart,
                      settings: s,
                      onChanged: (v) { setState(() => _autoStart = v); _saveSettings(); },
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      title:    context.tr('minimize_to_tray'),
                      subtitle: context.tr('behavior_minimize_to_tray_subtitle'),
                      value:    _minimizeToTray,
                      settings: s,
                      onChanged: (v) { setState(() => _minimizeToTray = v); _saveSettings(); },
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      title:    context.tr('start_minimized'),
                      subtitle: context.tr('behavior_start_minimized_subtitle'),
                      value:    _startMinimized,
                      settings: s,
                      onChanged: (v) { setState(() => _startMinimized = v); _saveSettings(); },
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      title:    context.tr('share_device_hwid'),
                      subtitle: context.tr('share_device_hwid_subtitle'),
                      value:    _shareDeviceHwid,
                      settings: s,
                      onChanged: (v) { setState(() => _shareDeviceHwid = v); _saveSettings(); },
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      title:    context.tr('autoconnect'),
                      subtitle: context.tr('behavior_autoconnect_subtitle'),
                      value:    _autoConnectLastServer,
                      settings: s,
                      onChanged: (v) { setState(() => _autoConnectLastServer = v); _saveSettings(); },
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

  Widget _buildBackground(BuildContext context, ThemeSettings s) {
    final mq   = MediaQuery.of(context);
    final path = ThemeManager().settings.backgroundImagePath!;
    final provider = ResizeImage(
      FileImage(File(path)),
      width:  (mq.size.width  * mq.devicePixelRatio).round(),
      height: (mq.size.height * mq.devicePixelRatio).round(),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: provider,
          fit:   BoxFit.cover,
          errorBuilder: (_, __, ___) {
            Future.microtask(() => ThemeManager().removeBackground());
            return Container(color: s.backgroundColor);
          },
        ),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: ThemeManager().settings.blurIntensity,
            sigmaY: ThemeManager().settings.blurIntensity,
          ),
          child: Container(
            color: Colors.black.withAlpha(
              ((1.0 - ThemeManager().settings.backgroundOpacity) * 255).round(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Переиспользуемый SwitchCard ─────────────────────────────────────────────
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
        title:    Text(title,    style: TextStyle(fontWeight: FontWeight.w500, color: s.textColor, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: s.secondaryTextColor)),
        value:       value,
        onChanged:   onChanged,
        activeColor: s.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
