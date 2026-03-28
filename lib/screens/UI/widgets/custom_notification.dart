import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class CustomNotification {
  static void show(
      BuildContext context, {
        required String message,
        NotificationType type = NotificationType.info,
        Duration duration = const Duration(seconds: 5),
        IconData? icon,
      }) {
    final themeManager = ThemeManager();
    Color backgroundColor;
    Color iconColor;
    IconData defaultIcon;

    switch (type) {
      case NotificationType.success:
        backgroundColor = const Color(0xFF10B981);
        iconColor       = Colors.white;
        defaultIcon     = Icons.check_circle;
        break;
      case NotificationType.error:
        backgroundColor = const Color(0xFFEF4444);
        iconColor       = Colors.white;
        defaultIcon     = Icons.error;
        break;
      case NotificationType.warning:
        backgroundColor = const Color(0xFFF59E0B);
        iconColor       = Colors.white;
        defaultIcon     = Icons.warning;
        break;
      case NotificationType.info:
      // Используем primaryColor (розовый) из темы
        backgroundColor = themeManager.settings.primaryColor;
        iconColor       = Colors.white;
        defaultIcon     = Icons.info;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    late Timer dismissTimer;

    overlayEntry = OverlayEntry(
      builder: (_) => _CustomNotificationWidget(
        message:         message,
        backgroundColor: backgroundColor,
        iconColor:       iconColor,
        icon:            icon ?? defaultIcon,
        onDismiss: () {
          dismissTimer.cancel();
          if (overlayEntry.mounted) overlayEntry.remove();
        },
      ),
    );

    overlay.insert(overlayEntry);

    dismissTimer = Timer(duration, () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
  }
}

enum NotificationType { success, error, warning, info }

// ─── Widget ───────────────────────────────────────────────────────────────────
class _CustomNotificationWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onDismiss;

  const _CustomNotificationWidget({
    required this.message,
    required this.backgroundColor,
    required this.iconColor,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_CustomNotificationWidget> createState() =>
      _CustomNotificationWidgetState();
}

class _CustomNotificationWidgetState extends State<_CustomNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _ctrl.isAnimating) return;
    _ctrl.reverse().then((_) { if (mounted) widget.onDismiss(); });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left:   20,
      right:  20,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color:        widget.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:      widget.backgroundColor.withOpacity(0.35),
                    blurRadius: 20,
                    offset:     const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding:    const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _dismiss,
                    child: Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
