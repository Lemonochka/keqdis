import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/services/ping_service.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/utils/server_name_utils.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final canSelect = !isAnyServerConnected || isConnected;

    return Opacity(
        opacity: canSelect ? 1.0 : 0.5,
        child: Card(
          color: isSelected
              ? themeManager.settings.primaryColor.withAlpha(51)
              : themeManager.settings.accentColor.withAlpha(77),
          elevation: isSelected ? 6 : 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: themeManager.settings.primaryColor, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: canSelect ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Флаг в круглом 3D контейнере
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2D3748),
                          Color(0xFF1A202C),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(102),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.white.withAlpha(13),
                          blurRadius: 4,
                          offset: const Offset(-2, -2),
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withAlpha(26),
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.grey.shade700,
                              Colors.grey.shade900,
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.public,
                          color: Colors.white54,
                          size: 24,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Информация (название + статус)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ServerNameUtils.cleanDisplayName(server.displayName),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? themeManager.settings.primaryColor
                                      : Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Источник
                        Row(
                          children: [
                            Icon(
                              server.subscriptionId != null
                                  ? Icons.rss_feed
                                  : Icons.edit,
                              size: 11,
                              color: Colors.white.withAlpha(128),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                server.subscriptionId != null
                                    ? server.subscriptionName ?? 'Подписка'
                                    : 'Добавлен вручную',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withAlpha(153),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Пинг (справа)
                  if (pingResult != null) ...[
                    const SizedBox(width: 12),
                    _buildPingInfo(pingResult!),
                  ],

                  const SizedBox(width: 12),

                  // Кнопки действий
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Пинг
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          icon: isPinging
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.speed, size: 16),
                          color: Colors.white70,
                          onPressed: isPinging ? null : onPing,
                          tooltip: 'Проверить пинг',
                          padding: EdgeInsets.zero,
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Избранное
                      SizedBox(
                        width: 32,
                        height: 28,
                        child: IconButton(
                          icon: Icon(
                            server.isFavorite ? Icons.star : Icons.star_border,
                            color: server.isFavorite ? Colors.amber : Colors.white54,
                            size: 18,
                          ),
                          onPressed: onFavoriteToggle,
                          tooltip: 'Избранное',
                          padding: EdgeInsets.zero,
                        ),
                      ),

                      // Удалить
                      SizedBox(
                        width: 32,
                        height: 28,
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onPressed: onDelete,
                          tooltip: 'Удалить',
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )
    );
  }

  Widget _buildPingInfo(PingResult result) {
    Color color;
    String text;

    if (!result.success) {
      color = Colors.red;
      text = 'Недоступен';
    } else if (result.latencyMs! < 100) {
      color = Colors.green;
      text = '${result.latencyMs}мс';
    } else if (result.latencyMs! < 300) {
      color = Colors.orange;
      text = '${result.latencyMs}мс';
    } else {
      color = Colors.red;
      text = '${result.latencyMs}мс';
    }

    return Row(
      children: [
        Icon(
          result.success ? Icons.speed : Icons.error_outline,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}