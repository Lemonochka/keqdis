import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/services/ping_service.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/utils/server_name_utils.dart';
import 'package:keqdis/localization/app_localization.dart';

class ServerListItem extends StatelessWidget {
  final ServerItem server;
  final bool isSelected;
  final bool isConnected;
  final PingResult? pingResult;
  final bool isPinging;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;
  final VoidCallback onPing;
  final bool isAnyServerConnected;
  final String? trafficInfo;
  final bool embeddedInGroup;

  const ServerListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.isConnected,
    this.pingResult,
    this.isPinging = false,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
    required this.onPing,
    this.isAnyServerConnected = false,
    this.trafficInfo,
    this.embeddedInGroup = false,
  });

  // Извлекаем протокол в первую очередь из config URI.
  String? _extractProtocol() {
    final cfg = server.config.trim().toLowerCase();
    if (cfg.startsWith('vless://')) return 'VLESS';
    if (cfg.startsWith('vmess://')) return 'VMess';
    if (cfg.startsWith('trojan://')) return 'Trojan';
    if (cfg.startsWith('ss://')) return 'SS';
    if (cfg.startsWith('hysteria://') || cfg.startsWith('hy2://')) {
      return 'Hysteria';
    }

    final name = '${server.displayName} ${server.subscriptionName ?? ''}'
        .toUpperCase();
    if (name.contains('VLESS')) return 'VLESS';
    if (name.contains('VMESS')) return 'VMess';
    if (name.contains('TROJAN')) return 'Trojan';
    if (name.contains('SS')) return 'SS';
    if (name.contains('HYSTERIA')) return 'Hysteria';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final s = themeManager.settings;
    final canSelect = !isAnyServerConnected || isConnected;
    final protocol = _extractProtocol();
    final baseContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          // Флаг страны (круглый)
          _CountryFlagAvatar(displayName: server.displayName),
          const SizedBox(width: 12),

          // Название + протокол + пинг
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ServerNameUtils.cleanDisplayName(server.displayName),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? s.primaryColor : s.textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Protocol badge
                    if (protocol != null) ...[
                      _ProtocolBadge(label: protocol, settings: s),
                      const SizedBox(width: 8),
                    ],
                    if (pingResult != null) _PingBadge(result: pingResult!),
                    if (trafficInfo != null && trafficInfo!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _TrafficBadge(text: trafficInfo!),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Кнопки действий
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка "пинг"
              _ActionIconBtn(
                icon: isPinging
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        Icons.speed,
                        size: 16,
                        color: s.secondaryTextColor,
                      ),
                onTap: isPinging ? null : onPing,
                tooltip: context.tr('vpn_ping_tooltip'),
              ),
              const SizedBox(width: 4),

              // Звезда / избранное
              _ActionIconBtn(
                icon: Icon(
                  server.isFavorite ? Icons.star : Icons.star_border,
                  size: 18,
                  color: server.isFavorite ? Colors.amber : s.secondaryTextColor,
                ),
                onTap: onFavoriteToggle,
                tooltip: context.tr('vpn_favorite_tooltip'),
              ),
              const SizedBox(width: 4),

              // Если подключён — кнопка-пауза вместо удаления
              if (isConnected)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.pause,
                    size: 18,
                    color: s.primaryColor,
                  ),
                )
              else
                _ActionIconBtn(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: s.secondaryTextColor,
                  ),
                  onTap: onDelete,
                  tooltip: context.tr('vpn_delete_tooltip'),
                ),
            ],
          ),
        ],
      ),
    );

    return Opacity(
      opacity: canSelect ? 1.0 : 0.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: embeddedInGroup
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: embeddedInGroup
              ? (isConnected ? s.primaryColor.withOpacity(0.12) : Colors.transparent)
              : (isConnected ? s.primaryColor.withOpacity(0.18) : s.cardColor),
          borderRadius: BorderRadius.circular(16),
          border: embeddedInGroup
              ? null
              : Border.all(
                  color: isConnected
                      ? s.primaryColor.withOpacity(0.5)
                      : s.borderColor,
                  width: isConnected ? 1.5 : 1.0,
                ),
          boxShadow: embeddedInGroup
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(s.isDark ? 0.15 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: canSelect ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            splashColor: s.primaryColor.withOpacity(0.1),
            highlightColor: Colors.transparent,
            child: baseContent,
          ),
        ),
      ),
    );
  }
}

// ─── Protocol badge ────────────────────────────────────────────────────────────
class _ProtocolBadge extends StatelessWidget {
  final String label;
  final ThemeSettings settings;

  const _ProtocolBadge({required this.label, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: settings.protocolBadgeBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: settings.protocolBadgeText,
        ),
      ),
    );
  }
}

// ─── Ping badge ────────────────────────────────────────────────────────────────
class _PingBadge extends StatelessWidget {
  final PingResult result;
  const _PingBadge({required this.result});

  Color get _color {
    if (!result.success) return Colors.red;
    final ms = result.latencyMs!;
    if (ms < 100) return const Color(0xFF4CAF50);
    if (ms < 300) return Colors.orange;
    return Colors.red;
  }

  String get _text {
    if (!result.success) return AppLocalization().t('vpn_ping_unavailable');
    return '${result.latencyMs} ms';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: TextStyle(
        fontSize: 13,
        color: _color,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _TrafficBadge extends StatelessWidget {
  final String text;
  const _TrafficBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.data_usage_rounded, size: 13, color: s.secondaryTextColor),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: s.secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Маленькая кнопка-иконка ──────────────────────────────────────────────────
class _ActionIconBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final String tooltip;

  const _ActionIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(width: 30, height: 30, child: Center(child: icon)),
      ),
    );
  }
}

// ─── Круглый флаг страны (44dp) ───────────────────────────────────────────────
class _CountryFlagAvatar extends StatelessWidget {
  final String displayName;
  const _CountryFlagAvatar({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final countryCode = ServerNameUtils.extractCountryCode(displayName);
    final isDark = ThemeManager().settings.isDark;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: countryCode != null
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: CountryFlag.fromCountryCode(
                  countryCode,
                  height: 44,
                  width: 66,
                ),
              )
            : Container(
                color: isDark
                    ? const Color(0xFF3A2020)
                    : const Color(0xFFFFD6D6),
                child: Icon(
                  Icons.public,
                  color: isDark ? Colors.white38 : Colors.pink.shade200,
                  size: 22,
                ),
              ),
      ),
    );
  }
}
