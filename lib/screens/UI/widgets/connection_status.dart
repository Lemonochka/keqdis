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
    final s = ThemeManager().settings;

    // Цвет точки статуса
    final dotColor = isConnected
        ? const Color(0xFF4CAF50)
        : s.secondaryTextColor.withOpacity(0.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        s.cardColor,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(
          color: isConnected
              ? const Color(0xFF4CAF50).withOpacity(0.4)
              : s.borderColor,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Индикаторная точка
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width:  10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: isConnected
                  ? [
                BoxShadow(
                  color:       const Color(0xFF4CAF50).withOpacity(0.5),
                  blurRadius:  6,
                  spreadRadius: 1,
                ),
              ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status,
            style: TextStyle(
              fontSize:   13,
              fontWeight: FontWeight.w600,
              color: isConnected
                  ? const Color(0xFF4CAF50)
                  : s.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
