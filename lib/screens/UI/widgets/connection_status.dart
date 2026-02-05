import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

class ConnectionStatus extends StatelessWidget {
  final String status;
  final bool isConnected;

  const ConnectionStatus({
    super.key,
    required this.status,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: themeManager.settings.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? Colors.green.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.grey,
              boxShadow: isConnected
                  ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            status,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isConnected ? Colors.green : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}